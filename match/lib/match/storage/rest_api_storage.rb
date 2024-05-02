require "fastlane_core/command_executor"
require "fastlane_core/configuration/configuration"
require "zlib"
require "base64"

require_relative "../options"
require_relative "../module"
require_relative "../spaceship_ensure"
require_relative "./interface"

module Match
  module Storage
    class RestAPIStorage < Interface
      attr_reader :username
      attr_reader :team_id
      attr_reader :team_name
      attr_reader :readonly
      attr_reader :api_key_path
      attr_reader :api_key

      attr_reader :rest_api_storage_download_proc
      attr_reader :rest_api_storage_upload_proc
      attr_reader :rest_api_storage_delete_proc
      attr_reader :rest_api_storage_list_proc
      attr_reader :rest_api_storage_auth_params
      attr_reader :rest_api_storage_path_separator

      def self.configure(params)
        UI.important("You are using a custom REST API for your storage.")

        return self.new(
          rest_api_storage_download_proc: params[:rest_api_storage_download_proc],
          rest_api_storage_upload_proc: params[:rest_api_storage_upload_proc],
          rest_api_storage_delete_proc: params[:rest_api_storage_delete_proc],
          rest_api_storage_list_proc: params[:rest_api_storage_list_proc],
          rest_api_storage_auth_params: params[:rest_api_storage_auth_params],
          rest_api_storage_path_separator: params[:rest_api_storage_path_separator],
          username: params[:username],
          team_id: params[:team_id],
          team_name: params[:team_name],
          readonly: params[:readonly],
          api_key_path: params[:api_key_path],
          api_key: params[:api_key]
        )
      end

      def initialize(rest_api_storage_download_proc: nil,
                     rest_api_storage_upload_proc: nil,
                     rest_api_storage_delete_proc: nil,
                     rest_api_storage_list_proc: nil,
                     rest_api_storage_auth_params: nil,
                     rest_api_storage_path_separator: nil,
                     username: nil,
                     team_id: nil,
                     team_name: nil,
                     readonly: nil,
                     api_key_path: nil,
                     api_key: nil)
        @rest_api_storage_download_proc = rest_api_storage_download_proc
        @rest_api_storage_upload_proc = rest_api_storage_upload_proc
        @rest_api_storage_delete_proc = rest_api_storage_delete_proc
        @rest_api_storage_list_proc = rest_api_storage_list_proc
        @rest_api_storage_auth_params = rest_api_storage_auth_params
        @rest_api_storage_path_separator = rest_api_storage_path_separator
        @username = username
        @team_id = team_id
        @team_name = team_name
        @readonly = readonly
        @api_key_path = api_key_path
        @api_key = api_key
      end

      # To make debugging easier, we have a custom exception here
      def prefixed_working_directory
        # We fall back to "*", which means certificates and profiles
        # from all teams that use this bucket would be installed. This is not ideal, but
        # unless the user provides a `team_id`, we can't know which one to use
        # This only happens if `readonly` is activated, and no `team_id` was provided
        @_folder_prefix ||= currently_used_team_id
        if @_folder_prefix.nil?
          # We use a `@_folder_prefix` variable, to keep state between multiple calls of this
          # method, as the value won't change. This way the warning is only printed once
          UI.important("Looks like you run `match` in `readonly` mode, and didn't provide a `team_id`. This will still work, however it HIGHLY recommended to provide a `team_id` in your Appfile or Matchfile. There are quota limits you will hit and Secrets manager is not used for fun!")
          @_folder_prefix = "*"
        end
        return File.join(working_directory, @_folder_prefix)
      end

      def download
        # Check if we already have a functional working_directory
        return if @working_directory && Dir.exist?(@working_directory)
        # No existing working directory, creating a new one now
        self.working_directory = Dir.mktmpdir

        list_opts = {
            auth_params: @rest_api_storage_auth_params
        }.compact

        files_to_download = @rest_api_storage_list_proc.call(list_opts)
        files_to_download.each do |file_identifier|
          download_opts = {
              file_id: file_identifier,
              auth_params: @rest_api_storage_auth_params
          }.compact
          binary_content = @rest_api_storage_download_proc.call(download_opts)
          file_name = decode_file_name(file_identifier)
          download_path = File.join(self.working_directory, file_name)
          FileUtils.mkdir_p(File.dirname(download_path))
          File.write(download_path, binary_content)
          UI.message("Successfully downloaded '#{file_name}' to '#{download_path}'")
        end
      end

      def upload_files(files_to_upload: [], custom_message: nil)
        files_to_upload.each do |file_path|
          file_id = rest_api_file_id(file_path)
          binary_content = File.read(file_path)
          upload_opts = {
            file_id: file_id,
            binary_content: binary_content,
            auth_params: @rest_api_storage_auth_params
          }
          @rest_api_storage_upload_proc.call(upload_opts)
          UI.message("Successfully uploaded '#{file_path}'")
        end
      end

      def delete_files(files_to_delete: [], custom_message: nil)
        files_to_delete.each do |file_path|
          file_id = rest_api_file_id(file_path)
          delete_opts = {
            file_id: file_id,
            auth_params: @rest_api_storage_auth_params
          }
          @rest_api_storage_delete_proc.call(delete_opts)
          UI.message("Successfully deleted '#{file_path}'")
        end
      end

      def list_files(file_name: "", file_ext: "")
        Dir[File.join(working_directory, self.team_id, "**", file_name, "*.#{file_ext}")]
      end

      def skip_docs
        false
      end

      def human_readable_description
        "Using a custom REST API for storage"
      end

      private

      def rest_api_file_id(file_name)
        sanitized = sanitize_file_name(file_name)
        encoded = encode_file_name(sanitized)
      end

      def sanitize_file_name(file_name)
        file_name.gsub("#{working_directory}/", "")
      end

      def ensure_file_name_encodable(file_name)
        if @rest_api_storage_path_separator && file_name.include?(@rest_api_storage_path_separator)
          UI.user_error!("The file name '#{file_name}' contains the path separator '#{@rest_api_storage_path_separator}' which is not allowed")
        end
      end

      def encode_file_name(file_name)
        # Use the path separator to transform the file system path into a custom object path
        @rest_api_storage_path_separator ? file_name.gsub(@rest_api_storage_path_separator, "___").gsub(File::SEPARATOR, @rest_api_storage_path_separator) : file_name
      end

      def decode_file_name(file_name)
        # Use the path separator to transform the custom object path back into a file system path
        @rest_api_storage_path_separator ? file_name.file_name.gsub(@rest_api_storage_path_separator, File::SEPARATOR).gsub("___", @rest_api_storage_path_separator) : file_name
      end

      def currently_used_team_id
        if self.readonly
          # In readonly mode, we still want to see if the user provided a team_id
          # see `prefixed_working_directory` comments for more details
          return self.team_id
        else
          UI.user_error!("The `team_id` option is required. fastlane cannot automatically determine portal team id via the App Store Connect API (yet)") if self.team_id.to_s.empty?

          spaceship = SpaceshipEnsure.new(self.username, self.team_id, self.team_name, api_token)
          return spaceship.team_id
        end
      end

      def api_token
        api_token = Spaceship::ConnectAPI::Token.from(hash: self.api_key, filepath: self.api_key_path)
        api_token ||= Spaceship::ConnectAPI.token
        return api_token
      end
    end
  end
end
