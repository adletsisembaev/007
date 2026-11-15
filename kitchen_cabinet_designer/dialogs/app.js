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
    materials: [],
    presets: [],
    ral: [],
    library: [],
    locale: 'ru',
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
    updateMaterialButtons();
    closePickers();
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

  // Recomputes visibility of every conditional element from scratch, so an
  // element hidden earlier becomes visible again when its conditions hold.
  function updateVisibility() {
    $all('[data-categories], [data-show-if]').forEach(function (el) {
      var visible = true;
      var cats = el.getAttribute('data-categories');
      if (cats) {
        visible = cats.split(/\s+/).indexOf(state.category) >= 0;
      }
      var showIf = el.getAttribute('data-show-if');
      if (visible && showIf) {
        visible = showIf.split(';').every(function (c) { return conditionHolds(c.trim()); });
      }
      el.hidden = !visible;
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

  // ------------------------------------------------------------ materials
  //
  // A material field holds a spec string (see material_library.rb):
  //   preset:<key>  |  color:#rrggbb  |  model:<name>
  // The picker is plain HTML, so it works in SketchUp's embedded browser,
  // which does not open the native colour chooser of <input type="color">.

  var SVG_NS = 'http://www.w3.org/2000/svg';
  var SLOT_KEYS = {
    carcass: 'carcass_material',
    front: 'front_material',
    back: 'back_material',
    drawer_box: 'drawer_box_material',
    hardware: 'hardware_material',
    plinth: 'plinth_material'
  };
  var FALLBACK_COLOR = '#cccccc';

  function parseSpec(spec) {
    var text = String(spec || '').trim();
    if (!text) { return null; }
    var i = text.indexOf(':');
    var kind = i < 0 ? '' : text.slice(0, i);
    if (['preset', 'color', 'model', 'ral', 'user', 'same'].indexOf(kind) < 0) {
      return { kind: 'model', value: text };
    }
    return { kind: kind, value: text.slice(i + 1) };
  }

  function findPreset(key) {
    for (var i = 0; i < state.presets.length; i++) {
      if (state.presets[i].key === key) { return state.presets[i]; }
    }
    return null;
  }

  function findModelMaterial(name) {
    for (var i = 0; i < state.materials.length; i++) {
      if (state.materials[i].name === name) { return state.materials[i]; }
    }
    return null;
  }

  function findRal(code) {
    for (var i = 0; i < state.ral.length; i++) {
      if (state.ral[i].code === code) { return state.ral[i]; }
    }
    return null;
  }

  function findLibraryItem(id) {
    for (var i = 0; i < state.library.length; i++) {
      if (state.library[i].id === id) { return state.library[i]; }
    }
    return null;
  }

  // { label, color, texture, textured } for a spec.
  function describeSpec(spec) {
    var parsed = parseSpec(spec);
    if (!parsed) { return { label: '', color: FALLBACK_COLOR, texture: null }; }
    if (parsed.kind === 'same') {
      var front = describeSpec(fieldByKey('front_material').value);
      return { label: t('material.same_front') + ' (' + front.label + ')', color: front.color,
               texture: front.texture, textured: front.textured };
    }
    if (parsed.kind === 'ral') {
      var ral = findRal(parsed.value);
      return { label: ral ? ral.label : 'RAL ' + parsed.value, color: ral ? ral.color : FALLBACK_COLOR, texture: null };
    }
    if (parsed.kind === 'user') {
      var item = findLibraryItem(parsed.value);
      if (!item) { return { label: parsed.value, color: FALLBACK_COLOR, texture: null }; }
      return { label: item.name, color: item.color || FALLBACK_COLOR, texture: item.texture,
               textured: item.kind === 'texture' };
    }
    if (parsed.kind === 'preset') {
      var preset = findPreset(parsed.value);
      if (preset) {
        return { label: preset.label, color: preset.color, texture: preset.texture, textured: !!preset.texture };
      }
    }
    if (parsed.kind === 'color') {
      return { label: t('material.custom_label', { hex: parsed.value }), color: parsed.value, texture: null };
    }
    var material = findModelMaterial(parsed.value);
    return { label: parsed.value, color: material ? material.color : FALLBACK_COLOR, texture: null,
             textured: material ? material.textured : true };
  }

  function paintSwatch(el, description) {
    el.style.backgroundColor = description.color;
    el.style.backgroundImage = description.texture ? 'url("' + description.texture + '")' : 'none';
  }

  function updateMaterialButtons() {
    $all('[data-material-button]').forEach(function (btn) {
      var field = fieldByKey(btn.getAttribute('data-material-button'));
      var description = describeSpec(field ? field.value : '');
      paintSwatch($('.swatch', btn), description);
      $('.swatch-label', btn).textContent = description.label;
      // The texture direction only matters for textured materials.
      var grain = $('.grain-select', btn.parentNode);
      if (grain) { grain.hidden = !description.textured; }
    });
  }

  function closePickers() {
    $all('.material-picker').forEach(function (picker) { picker.hidden = true; });
    $all('[data-material-button]').forEach(function (btn) { btn.classList.remove('open'); });
  }

  function selectMaterial(key, spec) {
    fieldByKey(key).value = spec;
    updateMaterialButtons();
    closePickers();
    scheduleValidation();
  }

  function makeChip(key, spec, description, current) {
    var chip = document.createElement('button');
    chip.type = 'button';
    chip.className = 'chip' + (spec === current ? ' selected' : '');
    chip.title = description.label;
    var swatch = document.createElement('span');
    swatch.className = 'swatch';
    paintSwatch(swatch, description);
    var label = document.createElement('span');
    label.className = 'chip-label';
    label.textContent = description.label;
    chip.appendChild(swatch);
    chip.appendChild(label);
    chip.addEventListener('click', function () { selectMaterial(key, spec); });
    return chip;
  }

  function makeLibraryChip(key, item, current) {
    var chip = makeChip(key, 'user:' + item.id, describeSpec('user:' + item.id), current);
    var remove = document.createElement('span');
    remove.className = 'chip-remove';
    remove.textContent = '\u00d7';
    remove.title = t('library.delete');
    remove.addEventListener('click', function (event) {
      event.stopPropagation();
      callRuby('library_remove', item.id);
    });
    chip.appendChild(remove);
    return chip;
  }

  function buildRal(picker, key, current) {
    var heading = document.createElement('div');
    heading.className = 'picker-heading';
    heading.textContent = t('material.group.ral');
    picker.appendChild(heading);
    var search = document.createElement('input');
    search.type = 'text';
    search.className = 'ral-search';
    search.placeholder = t('material.ral_search');
    picker.appendChild(search);
    var grid = document.createElement('div');
    grid.className = 'chip-grid ral-grid';
    picker.appendChild(grid);
    function render() {
      var query = search.value.trim().toLowerCase();
      grid.innerHTML = '';
      state.ral.forEach(function (ral) {
        if (query && ral.label.toLowerCase().indexOf(query) < 0) { return; }
        var spec = 'ral:' + ral.code;
        grid.appendChild(makeChip(key, spec, describeSpec(spec), current));
      });
    }
    search.addEventListener('input', render);
    render();
  }

  function buildLibrary(picker, key, current) {
    var chips = state.library.map(function (item) { return makeLibraryChip(key, item, current); });
    var grid = addGroup(picker, t('material.group.library'), chips);
    if (!chips.length) {
      var empty = document.createElement('div');
      empty.className = 'hint';
      empty.textContent = t('library.empty');
      grid.appendChild(empty);
    }
    var actions = document.createElement('div');
    actions.className = 'library-actions';
    [['library.add_texture', 'library_add_texture'], ['library.add_folder', 'library_add_folder']].forEach(function (pair) {
      var button = document.createElement('button');
      button.type = 'button';
      button.textContent = t(pair[0]);
      button.addEventListener('click', function () {
        state.libraryTarget = key;
        callRuby(pair[1]);
      });
      actions.appendChild(button);
    });
    picker.appendChild(actions);

    var form = document.createElement('div');
    form.className = 'library-color';
    var name = document.createElement('input');
    name.type = 'text';
    name.placeholder = t('library.color_name');
    var hex = document.createElement('input');
    hex.type = 'text';
    hex.className = 'hex-input';
    hex.placeholder = t('material.custom_placeholder');
    hex.maxLength = 7;
    var add = document.createElement('button');
    add.type = 'button';
    add.textContent = t('library.add_color');
    var error = document.createElement('div');
    error.className = 'field-error';
    add.addEventListener('click', function () {
      var value = hex.value.trim().toLowerCase();
      if (value && value.charAt(0) !== '#') { value = '#' + value; }
      if (!/^#[0-9a-f]{6}$/.test(value)) {
        error.textContent = t('material.custom_invalid');
        return;
      }
      state.libraryTarget = key;
      callRuby('library_add_color', { name: name.value, color: value });
    });
    form.appendChild(name);
    form.appendChild(hex);
    form.appendChild(add);
    picker.appendChild(form);
    picker.appendChild(error);
    var hint = document.createElement('div');
    hint.className = 'hint';
    hint.textContent = t('library.hint');
    picker.appendChild(hint);
  }

  function addGroup(picker, title, chips) {
    var heading = document.createElement('div');
    heading.className = 'picker-heading';
    heading.textContent = title;
    picker.appendChild(heading);
    var grid = document.createElement('div');
    grid.className = 'chip-grid';
    chips.forEach(function (chip) { grid.appendChild(chip); });
    picker.appendChild(grid);
    return grid;
  }

  function buildCustomColor(picker, key, current) {
    var heading = document.createElement('div');
    heading.className = 'picker-heading';
    heading.textContent = t('material.group.custom');
    picker.appendChild(heading);

    var row = document.createElement('div');
    row.className = 'custom-color';
    var parsed = parseSpec(current);
    var start = parsed && parsed.kind === 'color' ? parsed.value : describeSpec(current).color;

    var preview = document.createElement('span');
    preview.className = 'swatch';
    preview.style.backgroundColor = start;

    // Opens a colour chooser where the browser supports it; the hex field
    // below always works.
    var native = document.createElement('input');
    native.type = 'color';
    native.value = /^#[0-9a-fA-F]{6}$/.test(start) ? start : FALLBACK_COLOR;

    var hex = document.createElement('input');
    hex.type = 'text';
    hex.value = start;
    hex.placeholder = t('material.custom_placeholder');
    hex.maxLength = 7;

    var apply = document.createElement('button');
    apply.type = 'button';
    apply.textContent = t('material.apply');

    var error = document.createElement('div');
    error.className = 'field-error';

    function normalized() {
      var value = hex.value.trim().toLowerCase();
      if (value && value.charAt(0) !== '#') { value = '#' + value; }
      return /^#[0-9a-f]{6}$/.test(value) ? value : null;
    }
    function applyColor() {
      var value = normalized();
      if (!value) {
        error.textContent = t('material.custom_invalid');
        return;
      }
      selectMaterial(key, 'color:' + value);
    }

    native.addEventListener('input', function () {
      hex.value = native.value;
      preview.style.backgroundColor = native.value;
      error.textContent = '';
    });
    hex.addEventListener('input', function () {
      var value = normalized();
      if (value) {
        preview.style.backgroundColor = value;
        native.value = value;
      }
      error.textContent = '';
    });
    hex.addEventListener('keydown', function (event) {
      if (event.key === 'Enter') {
        event.preventDefault();
        applyColor();
      }
    });
    apply.addEventListener('click', applyColor);

    row.appendChild(preview);
    row.appendChild(native);
    row.appendChild(hex);
    row.appendChild(apply);
    picker.appendChild(row);
    picker.appendChild(error);
  }

  function buildPicker(key) {
    var picker = $('[data-picker-for="' + key + '"]');
    var current = fieldByKey(key).value;
    picker.innerHTML = '';

    if (key === 'plinth_material') {
      addGroup(picker, t('field.plinth_material'), [makeChip(key, 'same:front', describeSpec('same:front'), current)]);
    }

    var colors = [];
    var textures = [];
    state.presets.forEach(function (preset) {
      var spec = 'preset:' + preset.key;
      var chip = makeChip(key, spec, describeSpec(spec), current);
      (preset.texture ? textures : colors).push(chip);
    });
    addGroup(picker, t('material.group.colors'), colors);
    addGroup(picker, t('material.group.textures'), textures);
    buildLibrary(picker, key, current);
    buildRal(picker, key, current);

    var modelChips = state.materials.map(function (material) {
      var spec = 'model:' + material.name;
      return makeChip(key, spec, describeSpec(spec), current);
    });
    var grid = addGroup(picker, t('material.group.model'), modelChips);
    if (!modelChips.length) {
      var empty = document.createElement('div');
      empty.className = 'hint';
      empty.textContent = t('material.model_empty');
      grid.appendChild(empty);
    }

    buildCustomColor(picker, key, current);
  }

  function togglePicker(key) {
    var picker = $('[data-picker-for="' + key + '"]');
    var opening = picker.hidden;
    closePickers();
    if (!opening) { return; }
    buildPicker(key);
    picker.hidden = false;
    $('[data-material-button="' + key + '"]').classList.add('open');
  }

  // -------------------------------------------------------------- preview

  function slotFill(slot) {
    var key = SLOT_KEYS[slot];
    var field = key ? fieldByKey(key) : null;
    return describeSpec(field ? field.value : '');
  }

  function clearPreview(caption) {
    var svg = $('#preview');
    while (svg.firstChild) { svg.removeChild(svg.firstChild); }
    $('#preview-caption').textContent = caption || '';
  }

  function renderPreview(preview, params) {
    clearPreview();
    var svg = $('#preview');
    var b = preview.bounds;
    var width = b[2] - b[0];
    var height = b[3] - b[1];
    var pad = Math.max(width, height) * 0.03;
    svg.setAttribute('viewBox', [b[0] - pad, -b[3] - pad, width + 2 * pad, height + 2 * pad].join(' '));

    var floor = document.createElementNS(SVG_NS, 'line');
    floor.setAttribute('x1', b[0] - pad);
    floor.setAttribute('x2', b[2] + pad);
    floor.setAttribute('y1', 0);
    floor.setAttribute('y2', 0);
    floor.setAttribute('stroke', '#999999');
    floor.setAttribute('stroke-dasharray', '4 3');
    floor.setAttribute('vector-effect', 'non-scaling-stroke');
    if (params.category === 'base') { svg.appendChild(floor); }

    // Textured materials are shown with their texture, 400 mm per tile.
    var defs = document.createElementNS(SVG_NS, 'defs');
    svg.appendChild(defs);
    var patterns = {};
    function fillFor(slot) {
      var description = slotFill(slot);
      if (!description.texture) { return description.color; }
      if (!patterns[description.texture]) {
        var id = 'tex' + Object.keys(patterns).length;
        var pattern = document.createElementNS(SVG_NS, 'pattern');
        pattern.setAttribute('id', id);
        pattern.setAttribute('patternUnits', 'userSpaceOnUse');
        pattern.setAttribute('width', 400);
        pattern.setAttribute('height', 400);
        var image = document.createElementNS(SVG_NS, 'image');
        image.setAttribute('href', description.texture);
        image.setAttribute('width', 400);
        image.setAttribute('height', 400);
        image.setAttribute('preserveAspectRatio', 'none');
        pattern.appendChild(image);
        defs.appendChild(pattern);
        patterns[description.texture] = 'url(#' + id + ')';
      }
      return patterns[description.texture];
    }

    preview.rects.forEach(function (r) {
      var rect = document.createElementNS(SVG_NS, 'rect');
      rect.setAttribute('x', r.x0);
      rect.setAttribute('y', -r.z1);
      rect.setAttribute('width', Math.max(r.x1 - r.x0, 0.1));
      rect.setAttribute('height', Math.max(r.z1 - r.z0, 0.1));
      rect.setAttribute('fill', fillFor(r.slot));
      rect.setAttribute('stroke', '#3a3f47');
      rect.setAttribute('stroke-width', '1');
      if (r.shape === 'cylinder') { rect.setAttribute('rx', (r.x1 - r.x0) / 4); }
      var title = document.createElementNS(SVG_NS, 'title');
      title.textContent = r.name;
      rect.appendChild(title);
      svg.appendChild(rect);
    });

    $('#preview-caption').textContent = t('label.preview', {
      w: formatNumber(width),
      h: formatNumber(height)
    });
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
        clearPreview(t('label.preview_unavailable'));
        return;
      }
      if (inSketchUp()) {
        state.lastValidated = collectParams();
        callRuby('validate', state.lastValidated);
      }
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
    $('#btn-refresh-materials').addEventListener('click', function () { callRuby('refresh_materials'); });
    $all('[data-material-button]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        togglePicker(btn.getAttribute('data-material-button'));
      });
    });
    $('#btn-export').addEventListener('click', function () {
      var options = {};
      $all('[data-export-key]').forEach(function (el) { options[el.getAttribute('data-export-key')] = el.value; });
      showStatus('info', t('msg.working'));
      callRuby('export', options);
    });
    $('#language-select').addEventListener('change', function () {
      callRuby('set_locale', $('#language-select').value);
    });
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

  // Applies interface strings without touching the values being edited.
  function applyLocale(msg, revalidate) {
    state.strings = msg.strings || state.strings;
    state.presets = msg.presets || state.presets;
    state.ral = msg.ral || state.ral;
    state.locale = msg.locale || state.locale;
    applyStrings();
    document.documentElement.lang = state.locale;
    var select = $('#language-select');
    if (select) { select.value = state.locale; }
    buildTypeOptions();
    updateMaterialButtons();
    closePickers();
    if (revalidate) { scheduleValidation(); }
  }

  var handlers = {
    init: function (msg) {
      state.cabinetTypes = msg.cabinetTypes || [];
      state.defaults = msg.defaults || {};
      state.lastUsed = msg.lastUsed || {};
      state.materials = msg.materials || [];
      state.library = msg.library || [];
      var exportOptions = msg.exportOptions || {};
      $all('[data-export-key]').forEach(function (el) {
        var value = exportOptions[el.getAttribute('data-export-key')];
        if (value !== undefined) { el.value = typeof value === 'number' ? formatNumber(value) : value; }
      });
      applyLocale(msg, false);
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
      if (msg.ok && msg.preview) {
        renderPreview(msg.preview, state.lastValidated || collectParams());
      } else {
        clearPreview(t('label.preview_unavailable'));
      }
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

    materials: function (msg) {
      state.materials = msg.materials || [];
      updateMaterialButtons();
      var open = $('.material-picker:not([hidden])');
      if (open) { buildPicker(open.getAttribute('data-picker-for')); }
    },

    library: function (msg) {
      state.library = msg.library || [];
      // A newly added item is selected for the material being edited.
      if (msg.added && state.libraryTarget) {
        selectMaterial(state.libraryTarget, 'user:' + msg.added);
      } else {
        updateMaterialButtons();
        var open = $('.material-picker:not([hidden])');
        if (open) { buildPicker(open.getAttribute('data-picker-for')); }
      }
    },

    locale: function (msg) {
      applyLocale(msg, true);
      showStatus('info', t('msg.language_restart'));
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
