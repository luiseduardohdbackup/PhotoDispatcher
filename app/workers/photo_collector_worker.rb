require 'tempfile'

PhotoThumbnailSizes = {
  :tinythumbnail => [32, 21],
  :largethumbnail => [300, 200],
}

class PhotoCollectorWorker < Workling::Base
  def collect(options = {})
    rf_path = options[:root_folder] || PHOTO_IMPORT_FOLDER
    root_folder = nil

    unless (rf_path and (root_folder = Pathname.new(rf_path).realpath).exist?)
      logger.fatal "Import folder '#{root_folder ? root_folder.to_s : rf_path}' doesn't exist, set it in config/environments/*"
      return false
    end

    lockfile = Lockfile.new(File.join(rf_path, ".lockfile"))
    begin
      lockfile.lock
    rescue
      logger.debug "Couldn't acquire lockfile"
      return false
    end

    begin
      # Walk the import folder looking for new files
      root_folder.find do |f|
        logger.debug "Inspecting '#{f.to_s}'..."
        ext = f.extname.downcase
        next unless f.file? and (ext.include? 'jpg' or ext.include? 'jpeg')

        relative_path = f.to_s.gsub(root_folder, "").downcase
        next if Photo.exists?(:relativepath => relative_path)

        exifdata = nil
        ar_opts = nil
        begin
          exifdata = EXIFR::JPEG.new(f.to_s).to_hash
          raise "Bad EXIF data" unless exifdata

          # Create thumbnails of the image
          ar_opts = PhotoThumbnailSizes.map do |type, resolution| 
            { type => build_thumbnails(type, resolution, f.to_s, options[:thumb_root_path]) }
          end
        rescue
          logger.warn "Failed to process image '#{f.to_s}': #{$!.message}"
          logger.debug $!.backtrace
          return false if options[:errors_are_fatal]
          next
        end

        # Whew! Actually do the work
        Photo.create(ar_opts) do |f|
          f.relativepath = relative_path
          f.exif_data_yaml = exifdata.to_yaml
        end
      end
    ensure
      lockfile.unlock
    end
    
    true
  end

private

  def build_thumbnails(type, resolution, input_file, thumb_root_path)
    f = Pathname.new(input_file)
    temp_out = Tempfile.new("pcw")

    command = "gm convert -resize #{resolution.join 'x'} \"#{f.to_s}\" \"#{temp_out.path}\""
    logger.debug "Running '#{command}'"
    `#{command}`
    raise "Failed to create #{type}: gm returned #{$?.exitstatus}" unless $?.success?

    thumb_path = Photo.thumbnail_path(type, f.dirname.to_s, temp_out.path, thumb_root_path)
    logger.debug "Moving file to '#{thumb_path}'"
    FileUtils.move temp_out.path, thumb_path
  end
end
