/*
 * Kitchen Cabinet Designer - dialog logic.
 *
 * Ruby -> JS: KCD.receive(message) where message.type is one of
 *   init, params, validation, result, status, target.
 * JS -> Ruby: sketchup.<callback>(jsonString), see ui/dialog_controller.rb.
 *
 * Ruby is the single source of truth for validation; this file only performs
 * an instant "is it a number" check while typing.
 */
(function () {
  'use strict';

  var VALIDATE_DELAY_MS = 300;
  var BUSY_TIMEOUT_MS = 20000;

  var state = {
    strings: {},
    cabinetTypes: [],
    defaults: {},
    lastUsed: {},
    category: 'base',
    valuesByCategory: {},
    editing: false,
    validateTimer: null,
    busyTimer: null
  };

  // ---------------------------------------------------------------- helpers

  function $(selector, root) {
    return (root || document).querySelector(selector);
  }

  function $all(selector, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(selector));
  }

  function t(key, vars) {
    var text = Object.prototype.hasOwnProperty.call(state.strings, key) ? state.strings[key] : key;
    if (!vars) { return text; }
    return text.replace(/%\{(\w+)\}/g, function (match, name) {
      return Object.prototype.hasOwnProperty.call(vars, name) ? String(vars[name]) : match;
    });
  }

  function inSketchUp() {
    return typeof window.sketchup === 'object' && window.sketchup !== null;
  }

  function callRuby(name, payload) {
    if (!inSketchUp() || typeof window.sketchup[name] !== 'function') {
      showStatus('error', t('msg.outside_sketchup'));
      return false;
    }
    try {
      if (payload === undefined) {
        window.sketchup[name]();
      } else {
        window.sketchup[name](JSON.stringify(payload));
      }
      return true;
    } catch (err) {
      showStatus('error', t('error.bridge', { message: err && err.message ? err.message : String(err) }));
      return false;
    }
  }

  function formatNumber(value) {
    var n = Number(value);
    if (!isFinite(n)) { return String(value); }
    return String(Math.round(n * 100) / 100);
  }

  // ------------------------------------------------------------------ i18n

  function applyStrings() {
    $all('[data-i18n]').forEach(function (el) {
      var key = el.getAttribute('data-i18n');
      if (Object.prototype.hasOwnProperty.call(state.strings, key)) {
        el.textContent = state.strings[key];
      }
    });
    document.title = t('dialog.title');
  }

  // ---------------------------------------------------------------- fields

  function fields() {
    return $all('[data-key]');
  }

  function fieldByKey(key) {
    return $('[data-key="' + key + '"]');
  }

  function isApplicable(el) {
    return !el.closest('[hidden]');
  }

  function readField(el) {
    var type = el.getAttribute('data-type');
    if (type === 'bool') { return el.checked; }
    return el.value;
  }

  function writeField(el, value) {
    var type = el.getAttribute('data-type');
    if (type === 'bool') {
      el.checked = value === true || value === 'true' || value === 1 || value === '1';
    } else if (type === 'mm' || type === 'int') {
      el.value = value === null || value === undefined ? '' : formatNumber(value);
    } else {
      el.value = value === null || value === undefined ? '' : String(value);
    }
  }

  function collectParams() {
    var params = { category: state.category };
    fields().forEach(function (el) {
      if (isApplicable(el)) {
        params[el.getAttribute('data-key')] = readField(el);
      }
    });
    return params;
  }

  // Values of all fields (including hidden ones) for the current category.
  function snapshotValues() {
    var values = {};
    fields().forEach(function (el) {
      values[el.getAttribute('data-key')] = readField(el);
    });
    return values;
  }

  function fillForm(values) {
    // cabinet_type options depend on the category, so build them first.
    buildTypeOptions();
    fields().forEach(function (el) {
      var key = el.getAttribute('data-key');
      if (Object.prototype.hasOwnProperty.call(values, key)) {
        writeField(el, values[key]);
      }
    });
    var typeSelect = fieldByKey('cabinet_type');
    if (typeSelect && typeSelect.selectedIndex < 0 && typeSelect.options.length) {
      typeSelect.selectedIndex = 0;
    }
    updateVisibility();
    clearFieldErrors();
  }

  function buildTypeOptions() {
    var select = fieldByKey('cabinet_type');
    if (!select) { return; }
    var current = select.value;
    select.innerHTML = '';
    state.cabinetTypes.forEach(function (type) {
      if (type.categories.indexOf(state.category) < 0) { return; }
      var option = document.createElement('option');
      option.value = type.id;
      option.textContent = t('type.' + type.id) + (type.implemented ? '' : ' ' + t('type.planned_suffix'));
      select.appendChild(option);
    });
    select.value = current;
  }

  // ------------------------------------------------------------ visibility

  function conditionHolds(condition) {
    var parts = condition.split('=');
    if (parts.length !== 2) { return true; }
    var key = parts[0].trim();
    var allowed = parts[1].split(',').map(function (v) { return v.trim(); });
    var el = fieldByKey(key);
    if (!el) { return false; }
    var value = el.getAttribute('data-type') === 'bool' ? String(el.checked) : el.value;
    return allowed.indexOf(value) >= 0;
  }

  function updateVisibility() {
    $all('[data-categories]').forEach(function (el) {
      var cats = el.getAttribute('data-categories').split(/\s+/);
      el.hidden = cats.indexOf(state.category) < 0;
    });
    $all('[data-show-if]').forEach(function (el) {
      if (el.hidden) { return; }
      var conditions = el.getAttribute('data-show-if').split(';');
      el.hidden = !conditions.every(function (c) { return conditionHolds(c.trim()); });
    });
    $all('[data-category-button]').forEach(function (btn) {
      btn.setAttribute('aria-checked', String(btn.getAttribute('data-category-button') === state.category));
    });
  }

  function setCategory(category, values) {
    if (category === state.category && !values) { return; }
    state.valuesByCategory[state.category] = snapshotValues();
    state.category = category;
    fillForm(values || state.valuesByCategory[category] || state.lastUsed[category] || state.defaults[category] || {});
    scheduleValidation();
  }

  // -------------------------------------------------------- errors, status

  function clearFieldErrors() {
    $all('[data-error-for]').forEach(function (el) { el.textContent = ''; });
    $all('.row.invalid').forEach(function (row) { row.classList.remove('invalid'); });
  }

  // Shows field errors next to their fields. Returns errors without a
  // visible field so that they can be shown in the status area.
  function showFieldErrors(errors) {
    clearFieldErrors();
    var unplaced = [];
    (errors || []).forEach(function (err) {
      var slot = err.field ? $('[data-error-for="' + err.field + '"]') : null;
      if (slot && isApplicable(slot)) {
        slot.textContent = slot.textContent ? slot.textContent + ' ' + err.message : err.message;
        var row = slot.closest('.row');
        if (row) { row.classList.add('invalid'); }
      } else {
        unplaced.push(err);
      }
    });
    return unplaced;
  }

  function showStatus(level, message, items) {
    var box = $('#status');
    box.className = 'status ' + level;
    box.textContent = message || '';
    if (items && items.length) {
      var list = document.createElement('ul');
      items.forEach(function (item) {
        var li = document.createElement('li');
        li.textContent = item.message || String(item);
        list.appendChild(li);
      });
      box.appendChild(list);
    }
    box.hidden = !message && !(items && items.length);
  }

  function hideStatus() {
    $('#status').hidden = true;
  }

  function setBusy(busy) {
    ['#btn-create', '#btn-update', '#btn-load'].forEach(function (id) {
      var btn = $(id);
      if (busy) {
        btn.setAttribute('data-was-disabled', String(btn.disabled));
        btn.disabled = true;
      } else if (btn.hasAttribute('data-was-disabled')) {
        btn.disabled = btn.getAttribute('data-was-disabled') === 'true';
        btn.removeAttribute('data-was-disabled');
      }
    });
    clearTimeout(state.busyTimer);
    if (busy) {
      state.busyTimer = setTimeout(function () { setBusy(false); }, BUSY_TIMEOUT_MS);
    }
    updateEditingUi();
  }

  function updateEditingUi() {
    var banner = $('#edit-target');
    banner.hidden = !state.editing;
    var update = $('#btn-update');
    if (!update.hasAttribute('data-was-disabled')) {
      update.disabled = !state.editing;
    }
  }

  // ------------------------------------------------------------ validation

  function quickCheck() {
    var errors = [];
    fields().forEach(function (el) {
      if (!isApplicable(el)) { return; }
      var type = el.getAttribute('data-type');
      if (type !== 'mm' && type !== 'int') { return; }
      var text = String(el.value).trim().replace(',', '.');
      if (text === '' || !isFinite(Number(text))) {
        var key = el.getAttribute('data-key');
        errors.push({ field: key, message: t('error.not_number', { field: t('field.' + key) }) });
      }
    });
    return errors;
  }

  function scheduleValidation() {
    clearTimeout(state.validateTimer);
    state.validateTimer = setTimeout(function () {
      var errors = quickCheck();
      if (errors.length) {
        showFieldErrors(errors);
        return;
      }
      if (inSketchUp()) { callRuby('validate', collectParams()); }
    }, VALIDATE_DELAY_MS);
  }

  // -------------------------------------------------------------- actions

  function submit(callback) {
    var errors = quickCheck();
    if (errors.length) {
      showFieldErrors(errors);
      showStatus('error', t('msg.fix_errors'));
      return;
    }
    showStatus('info', t('msg.working'));
    if (callRuby(callback, collectParams())) { setBusy(true); }
  }

  function resetDefaults() {
    fillForm(state.defaults[state.category] || {});
    showStatus('info', t('msg.reset_done'));
    scheduleValidation();
  }

  function bindEvents() {
    $all('[data-category-button]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        setCategory(btn.getAttribute('data-category-button'));
      });
    });
    fields().forEach(function (el) {
      var handler = function () {
        updateVisibility();
        scheduleValidation();
      };
      el.addEventListener('input', handler);
      el.addEventListener('change', handler);
    });
    $('#btn-create').addEventListener('click', function () { submit('create_cabinet'); });
    $('#btn-update').addEventListener('click', function () { submit('update_cabinet'); });
    $('#btn-load').addEventListener('click', function () { callRuby('load_selected'); });
    $('#btn-reset').addEventListener('click', resetDefaults);
    $('#btn-close').addEventListener('click', function () {
      if (!callRuby('close')) { window.close(); }
    });
    $('#btn-stop-editing').addEventListener('click', function () {
      state.editing = false;
      updateEditingUi();
      callRuby('clear_target');
    });
  }

  // ------------------------------------------------------- Ruby messages

  var handlers = {
    init: function (msg) {
      state.strings = msg.strings || {};
      state.cabinetTypes = msg.cabinetTypes || [];
      state.defaults = msg.defaults || {};
      state.lastUsed = msg.lastUsed || {};
      applyStrings();
      $('#version').textContent = t('label.version', { version: msg.version || '' });
      state.category = 'base';
      fillForm(state.lastUsed.base || state.defaults.base || {});
      hideStatus();
      scheduleValidation();
    },

    params: function (msg) {
      var params = msg.params || {};
      var category = params.category || state.category;
      setCategory(category, params);
    },

    validation: function (msg) {
      var unplaced = showFieldErrors(msg.errors);
      if (unplaced.length) {
        showStatus('error', t('msg.fix_errors'), unplaced);
      } else if ($('#status').classList.contains('error')) {
        hideStatus();
      }
    },

    result: function (msg) {
      setBusy(false);
      if (msg.ok) {
        clearFieldErrors();
        var warnings = msg.warnings || [];
        showStatus(warnings.length ? 'warn' : 'ok', msg.message, warnings);
      } else {
        var unplaced = showFieldErrors(msg.errors);
        showStatus('error', msg.message, unplaced);
      }
    },

    status: function (msg) {
      setBusy(false);
      showStatus(msg.level || 'info', msg.message);
    },

    target: function (msg) {
      state.editing = !!msg.name;
      $('#edit-target-label').textContent = msg.name ? t('label.editing', { name: msg.name }) : '';
      updateEditingUi();
    }
  };

  window.KCD = {
    receive: function (msg) {
      try {
        var handler = msg && handlers[msg.type];
        if (handler) { handler(msg); }
      } catch (err) {
        setBusy(false);
        showStatus('error', t('error.bridge', { message: err && err.message ? err.message : String(err) }));
      }
    }
  };

  document.addEventListener('DOMContentLoaded', function () {
    bindEvents();
    updateVisibility();
    updateEditingUi();
    if (inSketchUp()) {
      callRuby('ready');
    } else {
      showStatus('error', 'This page must be opened from SketchUp (Extensions > Kitchen Cabinet Designer).');
    }
  });
}());
