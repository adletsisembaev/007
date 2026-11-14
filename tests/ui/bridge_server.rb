# frozen_string_literal: true

# Validation bridge for dialog_test.js: reads raw params (one JSON per line)
# on stdin and answers with the dialog's 'validation' message on stdout.
$stdout.sync = true
require_relative '../test_helper'
require 'json'
K = KitchenCabinetDesigner
while (line = $stdin.gets)
  raw = JSON.parse(line)
  r = K::Validation.check(raw); m = r.to_h.merge('type'=>'validation')
  m['preview'] = K::Geometry::Layout.preview(r.params) if r.ok?
  puts JSON.generate(m)
end
