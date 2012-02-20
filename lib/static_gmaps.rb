# The MIT License
#
# Copyright (c) 2010 Sebastian Gräßl <sebastian@validcode.me>
# Original Version from John Wulff, modified by Daniel Mattes
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'net/http'

module StaticGmaps
  @@version = '0.0.5'

  #map
  @@maximum_url_size = 1978
  @@maximum_markers  = 50
  @@default_center   = [ 0, 0 ]
  @@default_zoom     = 1
  @@default_scale    = 1
  @@default_size     = [ 500, 400 ]
  @@default_map_type = :roadmap
  @@default_sensor   = false



  #marker
  @@default_latitude        = nil
  @@default_longitude       = nil
  @@default_color           = nil
  @@default_label           = nil
  @@default_icon            = nil
  @@valid_colors            = [ :red, :green, :blue ]

  [:version, :maximum_url_size, :maximum_markers, :default_center, :default_zoom, :default_scale, :default_size, :default_map_type,
  :default_latitude, :default_longitude, :default_color, :default_label, :valid_colors, :default_icon, :default_sensor].each do |sym|
    class_eval <<-EOS
      def self.#{sym}
        @@#{sym}
      end

      def self.#{sym}=(obj)
        @@#{sym} = obj
      end
    EOS
  end

  class Map


    attr_accessor :center,
                  :zoom,
                  :scale,
                  :size,
                  :map_type,
                  :markers,
                  :sensor

    def initialize(options = {})
      self.center   = options[:center]
      self.zoom     = options[:zoom]     || StaticGmaps::default_zoom
      self.scale    = options[:scale]    || StaticGmaps::default_zoom
      self.size     = options[:size]     || StaticGmaps::default_size
      self.map_type = options[:map_type] || StaticGmaps::default_map_type
      self.sensor   = options[:sensor]   || StaticGmaps::default_sensor
      self.markers  = options[:markers]  || [ ]
    end

    def width
      size[0]
    end

    def height
      size[1]
    end

    # http://code.google.com/apis/maps/documentation/staticmaps/index.html#URL_Parameters
    def url
      raise MissingArgument.new("Size must be set before a url can be generated for Map.") if !size || !size[0] || !size[1]

      if(!self.center && !(markers && markers.size >= 1))
        self.center = StaticGmaps::default_center
      end

      if !(markers && markers.size >= 1)
        raise MissingArgument.new("Center must be set before a url can be generated for Map (or multiple markers can be specified).") if !center
        raise MissingArgument.new("Zoom must be set before a url can be generated for Map (or multiple markers can be specified).") if !zoom
      end
      raise "Google will not display more than #{StaticGmaps::maximum_markers} markers." if markers && markers.size > StaticGmaps::maximum_markers
      parameters = {}
      parameters[:size]     = "#{size[0]}x#{size[1]}"
      parameters[:map_type] = "#{map_type}"               if map_type
      parameters[:center]   = "#{center[0]},#{center[1]}" if center
      parameters[:zoom]     = "#{zoom}"                   if zoom
      parameters[:scale]    = "#{scale}"                  if scale
      parameters[:markers]  = "#{grouped_markers_fragements.join('&markers=')}"   if grouped_markers_fragements
      parameters[:sensor]   = "#{sensor}"

      parameters = parameters.to_a.sort { |a, b| a[0].to_s <=> b[0].to_s }
      parameters = parameters.collect { |parameter| "#{parameter[0]}=#{parameter[1]}" }
      parameters = parameters.join '&'
      x = "http://maps.google.com/maps/api/staticmap?#{parameters}"
      raise "Google doesn't like the url to be longer than #{StaticGmaps::maximum_url_size} characters.  Try fewer or less precise markers." if x.size > StaticGmaps::maximum_url_size
      return x
    end

    def grouped_markers_fragements
      if markers && markers.any?
        grouped = markers.group_by {|marker|
          if marker.icon then
            "icon:#{marker.icon}"
          elsif marker.color and marker.label then
            "color:#{marker.color}|label:#{marker.label}"
          elsif marker.color then
            "color:#{marker.color}"
          elsif marker.label then
            "label:#{marker.label}"
          else
            ""
          end
        }
        return grouped.collect{|group, gmarkers|
          "#{group}|" + gmarkers.collect{|marker| marker.url_fragment }.join('|')
        }
      else
        return nil
      end
    end

    def to_blob
      fetch
      return @blob
    end

    private
      def fetch
        if !@last_fetched_url || @last_fetched_url != url || !@blob
          uri = URI.parse url
          request = Net::HTTP::Get.new uri.path
          response = Net::HTTP.start(uri.host, uri.port) { |http| http.request request }
          @blob = response.body
          @last_fetched_url = url
        end
      end
  end

  # http://code.google.com/apis/maps/documentation/staticmaps/index.html#Markers
  class Marker

    attr_accessor :latitude,
                  :longitude,
                  :color,
                  :label,
                  :icon

    def initialize(options = {})
      self.latitude        = options[:latitude]        || StaticGmaps::default_latitude
      self.longitude       = options[:longitude]       || StaticGmaps::default_longitude
      self.color           = options[:color]           || StaticGmaps::default_color
      self.label           = options[:label]           || StaticGmaps::default_label
      self.icon            = options[:icon]            || StaticGmaps::default_icon
    end

    def color=(value)
      if value
        value = value.to_s.downcase.to_sym
        if !StaticGmaps::valid_colors.include?(value)
          raise ArgumentError.new("#{value} is not a supported color.  Supported colors are #{StaticGmaps::valid_colors.join(', ')}.")
        end
      end
      @color = value
    end

    def label=(value)
      if value
        value = value.to_s.upcase.to_sym
      end
      @label = value
    end

    def icon=(value)
      @icon = value
    end

    def url_fragment
      raise MissingArgument.new("Latitude must be set before a url_fragment can be generated for Marker.") if !latitude
      raise MissingArgument.new("Longitude must be set before a url_fragment can be generated for Marker.") if !longitude
      return "#{latitude},#{longitude}"
    end
  end
end