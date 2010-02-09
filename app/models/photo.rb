class Photo < ActiveRecord::Base
  validates_uniqueness_of :relativepath
  validates_presence_of :tinythumbnail
  validates_presence_of :largethumbnail

  validate :relativepath_doesnt_escape_photo_dir

  def relativepath_doesnt_escape_photo_dir
    errors.add_to_base("absolutepath '#{relativepath}' is outside import folder") unless absolutepath
  end

  def absolutepath
    pn = nil
    begin
      pn = Pathname.new(File.join(Photo.photo_import_folder, relativepath)).realpath
      raise "Fail" unless pn.exist? and pn.to_s.starts_with? Photo.photo_import_folder
    rescue
      logger.error "absolutepath '#{relativepath}' is outside import folder: #{$!.message}\n#{$!.backtrace}"
      logger.debug "expected is '#{Photo.photo_import_folder}'"
      return nil
    end

    pn.to_s
  end

  def filename
    relativepath.gsub /^.*\/([^\/]*)$/, '\1'
  end

  def exif_data
    @exif_data || (@exif_data = YAML.load(exif_data_yaml))
  end

  def lat_lng
    return nil unless exif_data[:gps_latitude] and exif_data[:gps_longitude]

    # Exifr returns this as a tuple of Rationals, like 50 deg, 30', 24"
    # Convert these to decimal values that GMaps understands
    [exif_data[:gps_latitude], exif_data[:gps_longitude]].zip([exif_data[:gps_latitude_ref], exif_data[:gps_longitude_ref]]).map do |x, ref|
      (x[0] + (x[1] / 60) + (x[2] / 3600)).to_f * (['N', 'E'].include?(ref) ? 1.0 : -1.0)
    end
  end

  class << self
    def thumbnail_path(type, enclosing_dir, full_image_path, image_cache_dir = nil)
      path_hash = Digest::SHA1.hexdigest(enclosing_dir)
      contents_hash = Digest::SHA1.file(full_image_path).hexdigest

      cachedir = image_cache_dir || PHOTO_THUMBNAIL_FOLDER
      raise "Thumbnail folder not set, set it in config/environments/*" unless cachedir
      File.join(cachedir, [path_hash, contents_hash, type].join('_')) + ".jpg"
    end

    def photo_import_folder
      return PHOTO_IMPORT_FOLDER
    end
  end
end
