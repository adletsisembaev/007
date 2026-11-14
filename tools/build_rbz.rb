# frozen_string_literal: true

# Packages the extension into an .rbz file (a ZIP archive) without any gems.
#
# Usage (from the repository root):
#   ruby tools/build_rbz.rb            -> dist/kitchen_cabinet_designer_<version>.rbz
#   ruby tools/build_rbz.rb out.rbz    -> custom output path
#
# Archive layout expected by SketchUp's Extension Manager:
#   kitchen_cabinet_designer.rb           (loader, at the archive root)
#   kitchen_cabinet_designer/...          (all extension files)

require 'zlib'
require 'fileutils'

module RbzBuilder
  ROOT = File.expand_path('..', __dir__)
  LOADER = 'kitchen_cabinet_designer.rb'
  FOLDER = 'kitchen_cabinet_designer'
  # Development files that must never be shipped.
  EXCLUDE = [/\.DS_Store\z/, /Thumbs\.db\z/i, /~\z/, /\.swp\z/].freeze

  # Minimal ZIP writer (deflate, no ZIP64): enough for an extension package.
  class ZipWriter
    Entry = Struct.new(:name, :crc, :compressed_size, :size, :offset, :dos_time, :dos_date)

    def initialize(io)
      @io = io
      @entries = []
    end

    def add(name, data, mtime)
      data = data.b
      deflated = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS).deflate(data, Zlib::FINISH)
      time, date = dos_timestamp(mtime)
      entry = Entry.new(name.b, Zlib.crc32(data), deflated.bytesize, data.bytesize, @io.pos, time, date)
      @io.write([0x04034b50, 20, 0x0800, 8, time, date, entry.crc,
                 entry.compressed_size, entry.size, entry.name.bytesize, 0].pack('VvvvvvVVVvv'))
      @io.write(entry.name)
      @io.write(deflated)
      @entries << entry
    end

    def finish
      start = @io.pos
      @entries.each do |e|
        @io.write([0x02014b50, 20, 20, 0x0800, 8, e.dos_time, e.dos_date, e.crc,
                   e.compressed_size, e.size, e.name.bytesize, 0, 0, 0, 0, 0o100644 << 16,
                   e.offset].pack('VvvvvvvVVVvvvvvVV'))
        @io.write(e.name)
      end
      size = @io.pos - start
      @io.write([0x06054b50, 0, 0, @entries.size, @entries.size, size, start, 0].pack('VvvvvVVv'))
    end

    private

    def dos_timestamp(time)
      time = Time.at(time.to_i).localtime
      time = Time.new(1980, 1, 1) if time.year < 1980
      [(time.hour << 11) | (time.min << 5) | (time.sec / 2),
       ((time.year - 1980) << 9) | (time.month << 5) | time.day]
    end
  end

  class << self
    def version
      source = File.read(File.join(ROOT, LOADER))
      source[/VERSION\s*=\s*'([^']+)'/, 1] or abort 'VERSION not found in loader'
    end

    def files
      list = Dir.glob(File.join(ROOT, FOLDER, '**', '*'), File::FNM_DOTMATCH)
                .select { |f| File.file?(f) }
                .map { |f| f.delete_prefix("#{ROOT}/") }
                .reject { |f| EXCLUDE.any? { |re| re.match?(f) } }
                .sort
      [LOADER] + list
    end

    def check!(names)
      required = %W[#{LOADER} #{FOLDER}/main.rb #{FOLDER}/dialogs/main.html
                    #{FOLDER}/locales/en.json #{FOLDER}/icons/cabinet_24.png
                    #{FOLDER}/icons/cabinet_32.png]
      missing = required - names
      abort "Missing files: #{missing.join(', ')}  (icons: run python3 tools/make_icons.py)" unless missing.empty?
    end

    def build(output)
      names = files
      check!(names)
      FileUtils.mkdir_p(File.dirname(output))
      File.open(output, 'wb') do |io|
        zip = ZipWriter.new(io)
        names.each do |name|
          path = File.join(ROOT, name)
          zip.add(name, File.binread(path), File.mtime(path))
        end
        zip.finish
      end
      puts "Built #{output} (#{names.size} files, #{File.size(output)} bytes)"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  output = ARGV[0] || File.join(RbzBuilder::ROOT, 'dist',
                                "kitchen_cabinet_designer_#{RbzBuilder.version}.rbz")
  RbzBuilder.build(File.expand_path(output))
end
