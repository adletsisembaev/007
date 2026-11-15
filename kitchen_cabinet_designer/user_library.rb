# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'securerandom'

module KitchenCabinetDesigner
  # The user's own materials, shared by all models on this computer:
  # * colours with a name/code (e.g. "Sirca XX-123"),
  # * textures imported from image files (e.g. decor images downloaded from a
  #   board manufacturer). Images are copied into the library folder, so the
  #   library keeps working when the original files are moved.
  #
  # Storage: <library dir>/library.json and <library dir>/textures/.
  # Plain Ruby (no SketchUp API).
  module UserLibrary
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .bmp .tif .tiff].freeze
    DEFAULT_TEXTURE_SIZE = 1000.0
    NAME_MAX = 80
    ID_PATTERN = /\A[a-z0-9]{8,32}\z/

    class Error < StandardError; end

    class << self
      attr_writer :dir

      # Library folder: %APPDATA%\KitchenCabinetDesigner on Windows,
      # ~/Library/Application Support/KitchenCabinetDesigner on macOS.
      def dir
        @dir ||= begin
          base =
            if ENV['APPDATA'] && !ENV['APPDATA'].empty?
              ENV['APPDATA']
            elsif RUBY_PLATFORM.include?('darwin')
              File.join(Dir.home, 'Library', 'Application Support')
            else
              File.join(Dir.home, '.config')
            end
          File.join(base, 'KitchenCabinetDesigner')
        end
      end

      def items
        data = read
        data['items'].is_a?(Array) ? data['items'] : []
      end

      def find(id)
        items.find { |item| item['id'] == id.to_s }
      end

      def texture_path(item)
        item && item['texture'] && File.join(texture_dir, item['texture'])
      end

      # Adds a colour. Returns the new item.
      def add_color(name, hex)
        hex = hex.to_s.strip.downcase
        raise Error, 'color' unless /\A#\h{6}\z/.match?(hex)

        add('kind' => 'color', 'name' => clean_name(name, hex), 'color' => hex)
      end

      # Copies an image file into the library. Returns the new item.
      def add_texture(path, name: nil, size: DEFAULT_TEXTURE_SIZE)
        path = path.to_s
        ext = File.extname(path).downcase
        raise Error, 'image' unless IMAGE_EXTENSIONS.include?(ext) && File.file?(path)

        id = new_id
        FileUtils.mkdir_p(texture_dir)
        FileUtils.cp(path, File.join(texture_dir, "#{id}#{ext}"))
        add('id' => id, 'kind' => 'texture',
            'name' => clean_name(name, File.basename(path, '.*')),
            'texture' => "#{id}#{ext}", 'size' => size.to_f, 'color' => '#bbbbbb')
      end

      # Adds every image in a folder (not recursive). Returns the new items.
      def add_folder(folder)
        Dir.children(folder.to_s).sort
           .map { |f| File.join(folder.to_s, f) }
           .select { |f| File.file?(f) && IMAGE_EXTENSIONS.include?(File.extname(f).downcase) }
           .map { |f| add_texture(f) }
      end

      def remove(id)
        data = read
        item = data['items'].find { |i| i['id'] == id.to_s }
        return false unless item

        data['items'].delete(item)
        write(data)
        path = texture_path(item)
        File.delete(path) if path && File.exist?(path)
        true
      end

      # Data for the dialog (thumbnail as a file:// URL).
      def dialog_items
        items.map do |item|
          {
            'id' => item['id'], 'kind' => item['kind'], 'name' => item['name'],
            'color' => item['color'],
            'texture' => item['kind'] == 'texture' ? file_url(texture_path(item)) : nil
          }
        end
      end

      def file_url(path)
        return nil unless path

        normalized = path.tr('\\', '/')
        encoded = normalized.gsub(%r{[^A-Za-z0-9\-._~:/]}) do |c|
          c.bytes.map { |b| format('%%%02X', b) }.join
        end
        encoded.start_with?('/') ? "file://#{encoded}" : "file:///#{encoded}"
      end

      private

      def texture_dir
        File.join(dir, 'textures')
      end

      def library_file
        File.join(dir, 'library.json')
      end

      def read
        return { 'items' => [] } unless File.exist?(library_file)

        data = JSON.parse(File.read(library_file, encoding: 'UTF-8'))
        data.is_a?(Hash) && data['items'].is_a?(Array) ? data : { 'items' => [] }
      rescue JSON::ParserError
        { 'items' => [] }
      end

      def write(data)
        FileUtils.mkdir_p(dir)
        tmp = "#{library_file}.tmp"
        File.write(tmp, JSON.pretty_generate(data), encoding: 'UTF-8')
        File.rename(tmp, library_file)
      end

      def add(item)
        item = { 'id' => new_id }.merge(item)
        data = read
        data['items'] << item
        write(data)
        item
      end

      def new_id
        SecureRandom.hex(6)
      end

      def clean_name(name, fallback)
        text = name.to_s.gsub(/[[:cntrl:]]/, ' ').strip
        text = fallback.to_s if text.empty?
        text[0, NAME_MAX]
      end
    end
  end
end
