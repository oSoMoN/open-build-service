module Webui
  module Packages
    class BuildLogController < Webui::WebuiController
      include BuildLogSupport
      include Webui::NotificationsHandler

      before_action :check_ajax, only: :update_build_log
      before_action :set_project
      before_action :set_repository
      before_action :set_architecture
      before_action :check_build_log_access
      before_action :handle_notification, only: :live_build_log

      def live_build_log
        @offset = 0
        @status = get_status(@project, @package_name, @repository, @architecture)
        @what_depends_on = Package.what_depends_on(@project, @package_name, @repository, @architecture)
        @finished = Buildresult.final_status?(status)

        set_job_status
      end

      def update_build_log
        @maxsize = 1024 * 64
        @first_request = params[:initial] == '1'
        @offset = params[:offset].to_i
        @status = get_status(@project, @package_name, @repository, @architecture)
        @finished = Buildresult.final_status?(@status)
        @size = get_size_of_log(@project, @package_name, @repository, @architecture)

        chunk_start = @offset
        chunk_end = @offset + @maxsize

        # Start at the most recent part to not get the full log from the begining just the last 64k
        if @first_request && (@finished || @size >= @maxsize)
          chunk_start = [0, @size - @maxsize].max
          chunk_end = @size
        end

        @log_chunk = get_log_chunk(@project, @package_name, @repository, @architecture, chunk_start, chunk_end)

        old_offset = @offset
        @offset = [chunk_end, @size].min
      rescue Timeout::Error, IOError
        @log_chunk = ''
      rescue Backend::Error => e
        case e.summary
        when /Logfile is not that big/
          @log_chunk = ''
        when /start out of range/
          # probably build compare has cut log and offset is wrong, reset offset
          @log_chunk = ''
          @offset = old_offset
        else
          @log_chunk = "No live log available: #{e.summary}\n"
          @finished = true
        end
      end

      private

      # Basically backend stores date in /source (package sources) and /build (package
      # build related). Logically build logs are stored in /build. Though build logs also
      # contain information related to source packages.
      # Thus before giving access to the build log, we need to ensure user has source access
      # rights.
      #
      # This before_filter checks source permissions for packages that belong
      # to local projects and local projects that link to other project's packages.
      #
      # If the check succeeds it sets @project and @package variables.
      def check_build_log_access
        @package_name = params[:package]

        # No need to check for the package, they only exist on the backend in this case
        if @project.scmsync
          @can_modify = User.possibly_nobody.can_modify?(@project)
          return
        end

        begin
          @package = Package.get_by_project_and_name(@project, @package_name, use_source: false,
                                                                              follow_multibuild: true)
        rescue Package::UnknownObjectError
          redirect_to project_show_path(@project.to_param),
                      error: "Couldn't find package '#{params[:package]}' in " \
                             "project '#{@project.to_param}'. Are you sure it exists?"
          return false
        end

        # NOTE: @package is a String for multibuild packages
        @package = Package.find_by_project_and_name(@project.name, Package.striping_multibuild_suffix(@package_name)) if @package.is_a?(String)

        unless @package.check_source_access?
          redirect_to package_show_path(project: @project.name, package: @package_name),
                      error: 'Could not access build log'
          return false
        end

        @can_modify = User.possibly_nobody.can_modify?(@project) || User.possibly_nobody.can_modify?(@package)

        true
      end

      def set_job_status
        @percent = nil

        begin
          jobstatus = get_job_status(@project, @package_name, @repository, @architecture)
          if jobstatus.present?
            js = Xmlhash.parse(jobstatus)
            @workerid = js.get('workerid')
            @buildtime = Time.now.to_i - js.get('starttime').to_i
            ld = js.get('lastduration')
            @percent = (@buildtime * 100) / ld.to_i if ld.present?
          end
        rescue StandardError
          @workerid = nil
          @buildtime = nil
        end
      end
    end
  end
end
