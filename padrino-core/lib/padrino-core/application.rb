module Padrino
  class ApplicationSetupError < RuntimeError #:nodoc:
  end

  ##
  # Subclasses of this become independent Padrino applications (stemming from Sinatra::Application)
  # These subclassed applications can be easily mounted into other Padrino applications as well.
  #
  class Application < Sinatra::Application
    register Padrino::Routing   # Support for advanced routing, controllers, url_for
    register Padrino::Rendering # Support for enhanced rendering with template detection

    class << self

      def inherited(subclass) #:nodoc:
        CALLERS_TO_IGNORE.concat(PADRINO_IGNORE_CALLERS)
        subclass.default_configuration!
        Padrino.set_load_paths File.join(subclass.root, "/models")
        Padrino.require_dependencies File.join(subclass.root, "/models.rb")
        Padrino.require_dependencies File.join(subclass.root, "/models/**/*.rb")
        super(subclass) # Loading the subclass inherited method
      end

      ##
      # Hooks into when a new instance of the application is created
      # This is used because putting the configuration into inherited doesn't
      # take into account overwritten app settings inside subclassed definitions
      # Only performs the setup first time application is initialized.
      #
      def new(*args, &bk)
        setup_application!
        super(*args, &bk)
      end

      ##
      # Reloads the application files from all defined load paths
      #
      # This method is used from our Padrino Reloader during development mode
      # in order to reload the source files.
      #
      # ==== Examples
      #
      #   MyApp.reload!
      #
      def reload!
        reset_routes! # remove all existing user-defined application routes
        Padrino.load_dependency(self.app_file)  # reload the app file
        load_paths.each { |path| Padrino.load_dependencies(File.join(self.root, path)) } # reload dependencies
      end

      ##
      # Resets application routes to only routes not defined by the user
      #
      # ==== Examples
      #
      #   MyApp.reset_routes!
      #
      def reset_routes!
        router.reset!
        default_routes!
      end

      ##
      # Setup the application by registering initializers, load paths and logger
      # Invoked automatically when an application is first instantiated
      #
      def setup_application!
        return if @_configured
        self.calculate_paths
        self.register_framework_extensions
        self.register_initializers
        self.require_load_paths
        self.disable :logging # We need do that as default because Sinatra use commonlogger.
        self.default_filters!
        self.default_routes!
        self.default_errors!
        I18n.load_path += self.locale_path
        I18n.reload!
        @_configured = true
      end

      protected
        ##
        # Defines default settings for Padrino application
        #
        def default_configuration!
          # Overwriting Sinatra defaults
          set :app_file, caller_files.first || $0 # Assume app file is first caller
          set :environment, Padrino.env
          set :raise_errors, true if development?
          set :reload, true if development?
          set :logging, false
          set :sessions, false
          set :public, Proc.new { Padrino.root('public', self.uri_root) }
          # Padrino specific
          set :uri_root, "/"
          set :reload, Proc.new { development? }
          set :app_name, self.to_s.underscore.to_sym
          set :default_builder, 'StandardFormBuilder'
          set :flash, defined?(Rack::Flash)
          set :authentication, false
          # Padrino locale
          set :locale_path, Proc.new { Dir[File.join(self.root, "/locale/**/*.{rb,yml}")] }
          # Plugin specific
          set :padrino_mailer, defined?(Padrino::Mailer)
          set :padrino_helpers, defined?(Padrino::Helpers)
        end

        ##
        # We need to add almost __sinatra__ images.
        #
        def default_routes!
          configure :development do
            get '/__sinatra__/:image.png' do
              filename = File.dirname(__FILE__) + "/images/#{params[:image]}.png"
              send_file filename
            end
          end
        end

        ##
        # This filter it's used for know the format of the request, and automatically set the content type.
        #
        def default_filters!
          before do
            @_content_type = :html
            response['Content-Type'] = 'text/html;charset=utf-8'
          end
        end

        ##
        # This log errors for production environments
        #
        def default_errors!
          configure :production do
            error ::Exception do
              boom = env['sinatra.error']
              logger.error ["#{boom.class} - #{boom.message}:", *boom.backtrace].join("\n ")
              response.status = 500
              content_type 'text/html'
              '<h1>Internal Server Error</h1>'
            end
          end
        end

        ##
        # Calculates any required paths after app_file and root have been properly configured
        # Executes as part of the setup_application! method
        #
        def calculate_paths
          raise ApplicationSetupError.new("Please define 'app_file' option for #{self.name} app!") unless self.app_file
          set :views, find_view_path if find_view_path
          set :images_path, File.join(self.public, "/images") unless self.respond_to?(:images_path)
        end

        ##
        # Requires the Padrino middleware
        #
        def register_initializers
          use Padrino::Logger::Rack    if Padrino.logger && Padrino.logger.level == 0
          use Padrino::Reloader::Rack  if reload?
          use Rack::Flash              if flash? && sessions?
        end

        ##
        # Registers all desired padrino extension helpers
        #
        def register_framework_extensions
          register Padrino::Mailer  if padrino_mailer?
          register Padrino::Helpers if padrino_helpers?
          register Padrino::Admin::AccessControl if authentication?
        end

        ##
        # Returns the load_paths for the application (relative to the application root)
        #
        def load_paths
          @load_paths ||= ["urls.rb", "config/urls.rb", "mailers/*.rb", "mailers.rb",
                           "controllers/**/*.rb", "controllers.rb", "helpers/**/*.rb", "helpers.rb"]
        end

        ##
        # Requires all files within the application load paths
        #
        def require_load_paths
          load_paths.each { |path| Padrino.require_dependencies(File.join(self.root, path)) }
        end

        ##
        # Returns the path to the views directory from root by returning the first that is found
        #
        def find_view_path
          @view_paths = ["views"].collect { |path| File.join(self.root, path) }
          @view_paths.find { |path| Dir[File.join(path, '/**/*')].any? }
        end
    end # self

    private
      def clean_backtrace(trace)
        return trace unless settings.clean_trace?
        trace.reject { |line|
          line =~ /lib\/sinatra.*\.rb|lib\/padrino.*\.rb/ ||
            (defined?(Gem) && line.include?(Gem.dir))
        }.map! { |line| line.gsub(/^\.\//, '') }
      end
  end # Application
end # Padrino