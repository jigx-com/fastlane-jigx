describe Match do
  describe Match::Runner do
    let(:keychain) { 'login.keychain' }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('MATCH_KEYCHAIN_NAME').and_return(keychain)
      allow(ENV).to receive(:[]).with('MATCH_KEYCHAIN_PASSWORD').and_return(nil)

      # There is another test
      ENV.delete('FASTLANE_TEAM_ID')
      ENV.delete('FASTLANE_TEAM_NAME')
    end

    ["10", "11"].each do |xcode_version|
      context "Xcode #{xcode_version}" do
        let(:generate_apple_certs) { xcode_version == "11" }
        before do
          allow(FastlaneCore::Helper).to receive(:mac?).and_return(true)
          allow(FastlaneCore::Helper).to receive(:xcode_version).and_return(xcode_version)

          stub_const('ENV', { "MATCH_PASSWORD" => '2"QAHg@v(Qp{=*n^' })
        end

        it "creates a new profile and certificate if it doesn't exist yet", requires_security: true do
          git_url = "https://github.com/fastlane/fastlane/tree/master/certificates"
          values = {
            app_identifier: "tools.fastlane.app",
            type: "appstore",
            git_url: git_url,
            shallow_clone: true,
            username: "flapple@something.com"
          }

          config = FastlaneCore::Configuration.create(Match::Options.available_options, values)
          repo_dir = Dir.mktmpdir
          cert_path = File.join(repo_dir, "something.cer")
          File.copy_stream("./match/spec/fixtures/existing/certs/distribution/Certificate.cer", cert_path)
          openssl = Match::Encryption::OpenSSL.new(
            keychain_name: "login.keychain",
            working_directory: repo_dir
          )
          openssl.encrypt_files(password: ENV.fetch("MATCH_PASSWORD", nil))
          profile_path = "./match/spec/fixtures/test.mobileprovision"
          keychain_path = FastlaneCore::Helper.keychain_path("login.keychain") # can be .keychain or .keychain-db
          destination = File.expand_path("~/Library/MobileDevice/Provisioning Profiles/98264c6b-5151-4349-8d0f-66691e48ae35.mobileprovision")

          fake_storage = "fake_storage"
          expect(Match::Storage::GitStorage).to receive(:configure).with(
            git_url: git_url,
            shallow_clone: true,
            skip_docs: false,
            git_branch: "master",
            git_full_name: nil,
            git_user_email: nil,
            clone_branch_directly: false,
            git_basic_authorization: nil,
            git_bearer_authorization: nil,
            git_private_key: nil,
            type: config[:type],
            generate_apple_certs: generate_apple_certs,
            platform: config[:platform],
            google_cloud_bucket_name: "",
            google_cloud_keys_file: "",
            google_cloud_project_id: "",
            skip_google_cloud_account_confirmation: false,
            s3_region: nil,
            s3_access_key: nil,
            s3_secret_access_key: nil,
            s3_bucket: nil,
            s3_object_prefix: nil,
            gitlab_project: nil,
            gitlab_host: 'https://gitlab.com',
            aws_secrets_manager_access_key: nil,
            aws_secrets_manager_force_delete_without_recovery: nil,
            aws_secrets_manager_prefix: nil,
            aws_secrets_manager_path_separator: nil,
            aws_secrets_manager_recovery_window_days: nil,
            aws_secrets_manager_region: nil,
            aws_secrets_manager_secret_access_key: nil,
            readonly: false,
            username: values[:username],
            team_id: nil,
            team_name: nil,
            api_key_path: nil,
            api_key: nil,
            skip_spaceship_ensure: false
          ).and_return(fake_storage)

          expect(fake_storage).to receive(:download).and_return(nil)
          expect(fake_storage).to receive(:clear_changes).and_return(nil)
          allow(fake_storage).to receive(:working_directory).and_return(repo_dir)
          allow(fake_storage).to receive(:prefixed_working_directory).and_return(repo_dir)
          expect(Match::Generator).to receive(:generate_certificate).with(config, :distribution, fake_storage.working_directory, specific_cert_type: nil).and_return(cert_path)
          expect(Match::Generator).to receive(:generate_provisioning_profile).with(params: config,
                                                                                   prov_type: :appstore,
                                                                                   certificate_id: "something",
                                                                                   certificate_serial_number: "665C0BF3BA7BFB7EFBC4789806719C8A",
                                                                                   app_identifier: values[:app_identifier],
                                                                                   force: false,
                                                                                   working_directory: fake_storage.working_directory).and_return(profile_path)
          expect(FastlaneCore::ProvisioningProfile).to receive(:install).with(profile_path, keychain_path).and_return(destination)
          expect(fake_storage).to receive(:save_changes!).with(
            files_to_commit: [
              File.join(repo_dir, "something.cer"),
              File.join(repo_dir, "something.p12"), # this is important, as a cert consists out of 2 files
              "./match/spec/fixtures/test.mobileprovision"
            ]
          )

          spaceship = "spaceship"
          allow(spaceship).to receive(:team_id).and_return("")
          expect(Match::SpaceshipEnsure).to receive(:new).and_return(spaceship)
          expect(spaceship).to receive(:certificates_exists).and_return(true)
          expect(spaceship).to receive(:profile_exists).and_return(true)
          expect(spaceship).to receive(:bundle_identifier_exists).and_return(true)
          expect(Match::Utils).to receive(:get_cert_info).and_return([["Common Name", "fastlane certificate name"]])

          Match::Runner.new.run(config)

          expect(ENV.fetch(Match::Utils.environment_variable_name(app_identifier: "tools.fastlane.app",
                                                                  type: "appstore"), nil)).to eql('98264c6b-5151-4349-8d0f-66691e48ae35')
          expect(ENV.fetch(Match::Utils.environment_variable_name_team_id(app_identifier: "tools.fastlane.app",
                                                                          type: "appstore"), nil)).to eql('439BBM9367')
          expect(ENV.fetch(Match::Utils.environment_variable_name_profile_name(app_identifier: "tools.fastlane.app",
                                                                               type: "appstore"), nil)).to eql('tools.fastlane.app AppStore')
          profile_path = File.expand_path('~/Library/MobileDevice/Provisioning Profiles/98264c6b-5151-4349-8d0f-66691e48ae35.mobileprovision')
          expect(ENV.fetch(Match::Utils.environment_variable_name_profile_path(app_identifier: "tools.fastlane.app",
                                                                               type: "appstore"), nil)).to eql(profile_path)
          expect(ENV.fetch(Match::Utils.environment_variable_name_certificate_name(app_identifier: "tools.fastlane.app",
                                                                                   type: "appstore"), nil)).to eql("fastlane certificate name")
        end

        it "uses existing certificates and profiles if they exist", requires_security: true do
          git_url = "https://github.com/fastlane/fastlane/tree/master/certificates"
          values = {
            app_identifier: "tools.fastlane.app",
            type: "appstore",
            git_url: git_url,
            username: "flapple@something.com"
          }

          config = FastlaneCore::Configuration.create(Match::Options.available_options, values)
          repo_dir = "./match/spec/fixtures/existing"
          cert1_path = "./match/spec/fixtures/existing/certs/distribution/Certificate.cer"
          cert2_path = "./match/spec/fixtures/existing/certs/distribution/Certificate2.cer"
          key1_path = "./match/spec/fixtures/existing/certs/distribution/PrivateKey.p12"
          key2_path = "./match/spec/fixtures/existing/certs/distribution/PrivateKey2.p12"

          fake_storage = "fake_storage"
          expect(Match::Storage::GitStorage).to receive(:configure).with(
            git_url: git_url,
            shallow_clone: false,
            skip_docs: false,
            git_branch: "master",
            git_full_name: nil,
            git_user_email: nil,
            clone_branch_directly: false,
            git_basic_authorization: nil,
            git_bearer_authorization: nil,
            git_private_key: nil,
            type: config[:type],
            generate_apple_certs: generate_apple_certs,
            platform: config[:platform],
            google_cloud_bucket_name: "",
            google_cloud_keys_file: "",
            google_cloud_project_id: "",
            skip_google_cloud_account_confirmation: false,
            s3_region: nil,
            s3_access_key: nil,
            s3_secret_access_key: nil,
            s3_bucket: nil,
            s3_object_prefix: nil,
            gitlab_project: nil,
            gitlab_host: 'https://gitlab.com',
            aws_secrets_manager_access_key: nil,
            aws_secrets_manager_force_delete_without_recovery: nil,
            aws_secrets_manager_prefix: nil,
            aws_secrets_manager_path_separator: nil,
            aws_secrets_manager_recovery_window_days: nil,
            aws_secrets_manager_region: nil,
            aws_secrets_manager_secret_access_key: nil,
            readonly: false,
            username: values[:username],
            team_id: nil,
            team_name: nil,
            api_key_path: nil,
            api_key: nil,
            skip_spaceship_ensure: false
          ).and_return(fake_storage)

          expect(fake_storage).to receive(:download).and_return(nil)
          expect(fake_storage).to receive(:clear_changes).and_return(nil)
          allow(fake_storage).to receive(:git_url).and_return(git_url)
          allow(fake_storage).to receive(:working_directory).and_return(repo_dir)
          allow(fake_storage).to receive(:prefixed_working_directory).and_return(repo_dir)

          fake_encryption = "fake_encryption"
          expect(Match::Encryption::OpenSSL).to receive(:new).with(keychain_name: fake_storage.git_url, working_directory: fake_storage.working_directory).and_return(fake_encryption)
          expect(fake_encryption).to receive(:decrypt_files).and_return(nil)

          expect(Match::Utils).to receive(:import).with(key1_path, keychain, password: nil).and_return(nil)
          expect(Match::Utils).to receive(:import).with(key2_path, keychain, password: nil).and_return(nil)
          expect(fake_storage).to_not(receive(:save_changes!))

          # To also install the certificate, fake that
          expect(FastlaneCore::CertChecker).to receive(:installed?).with(cert1_path, in_keychain: nil).and_return(false)
          expect(Match::Utils).to receive(:import).with(cert1_path, keychain, password: nil).and_return(nil)
          expect(FastlaneCore::CertChecker).to receive(:installed?).with(cert2_path, in_keychain: nil).and_return(false)
          expect(Match::Utils).to receive(:import).with(cert2_path, keychain, password: nil).and_return(nil)

          spaceship = "spaceship"
          allow(spaceship).to receive(:team_id).and_return("")
          expect(Match::SpaceshipEnsure).to receive(:new).and_return(spaceship)
          expect(spaceship).to receive(:certificates_exists).and_return(true)
          expect(spaceship).to receive(:profile_exists).and_return(true)
          expect(spaceship).to receive(:bundle_identifier_exists).and_return(true)
          expect(Match::Utils).to receive(:get_cert_info).and_return([["Common Name", "fastlane certificate name"]]).exactly(3).times

          allow(Match::Utils).to receive(:is_cert_valid?).and_return(true)

          Match::Runner.new.run(config)

          expect(ENV.fetch(Match::Utils.environment_variable_name(app_identifier: "tools.fastlane.app",
                                                                  type: "appstore"), nil)).to eql('c3e20987-ffea-4d11-b037-e8bf0a102561')
          expect(ENV.fetch(Match::Utils.environment_variable_name_team_id(app_identifier: "tools.fastlane.app",
                                                                          type: "appstore"), nil)).to eql('VQVYM88YJ2')
          expect(ENV.fetch(Match::Utils.environment_variable_name_profile_name(app_identifier: "tools.fastlane.app",
                                                                               type: "appstore"), nil)).to eql('Fastlane PR Unit Tests')
          profile_path = File.expand_path('~/Library/MobileDevice/Provisioning Profiles/c3e20987-ffea-4d11-b037-e8bf0a102561.mobileprovision')
          expect(ENV.fetch(Match::Utils.environment_variable_name_profile_path(app_identifier: "tools.fastlane.app",
                                                                               type: "appstore"), nil)).to eql(profile_path)
          expect(ENV.fetch(Match::Utils.environment_variable_name_certificate_name(app_identifier: "tools.fastlane.app",
                                                                                   type: "appstore"), nil)).to eql("fastlane certificate name")
        end

        it "fails because of an outdated certificate", requires_security: true do
          git_url = "https://github.com/fastlane/fastlane/tree/master/certificates"
          values = {
            app_identifier: "tools.fastlane.app",
            type: "appstore",
            git_url: git_url,
            username: "flapple@something.com"
          }

          config = FastlaneCore::Configuration.create(Match::Options.available_options, values)
          repo_dir = "./match/spec/fixtures/existing"
          cert1_path = "./match/spec/fixtures/existing/certs/distribution/Certificate.cer"
          cert2_path = "./match/spec/fixtures/existing/certs/distribution/Certificate2.cer"
          key1_path = "./match/spec/fixtures/existing/certs/distribution/PrivateKey.p12"
          key2_path = "./match/spec/fixtures/existing/certs/distribution/PrivateKey2.p12"

          fake_storage = "fake_storage"
          expect(Match::Storage::GitStorage).to receive(:configure).with(
            git_url: git_url,
            shallow_clone: false,
            skip_docs: false,
            git_branch: "master",
            git_full_name: nil,
            git_user_email: nil,
            clone_branch_directly: false,
            git_basic_authorization: nil,
            git_bearer_authorization: nil,
            git_private_key: nil,
            type: config[:type],
            generate_apple_certs: generate_apple_certs,
            platform: config[:platform],
            google_cloud_bucket_name: "",
            google_cloud_keys_file: "",
            google_cloud_project_id: "",
            skip_google_cloud_account_confirmation: false,
            s3_region: nil,
            s3_access_key: nil,
            s3_secret_access_key: nil,
            s3_bucket: nil,
            s3_object_prefix: nil,
            gitlab_project: nil,
            gitlab_host: 'https://gitlab.com',
            aws_secrets_manager_access_key: nil,
            aws_secrets_manager_force_delete_without_recovery: nil,
            aws_secrets_manager_prefix: nil,
            aws_secrets_manager_path_separator: nil,
            aws_secrets_manager_recovery_window_days: nil,
            aws_secrets_manager_region: nil,
            aws_secrets_manager_secret_access_key: nil,
            readonly: false,
            username: values[:username],
            team_id: nil,
            team_name: nil,
            api_key_path: nil,
            api_key: nil,
            skip_spaceship_ensure: false
          ).and_return(fake_storage)

          expect(fake_storage).to receive(:download).and_return(nil)
          expect(fake_storage).to receive(:clear_changes).and_return(nil)
          allow(fake_storage).to receive(:git_url).and_return(git_url)
          allow(fake_storage).to receive(:working_directory).and_return(repo_dir)
          allow(fake_storage).to receive(:prefixed_working_directory).and_return(repo_dir)

          fake_encryption = "fake_encryption"
          expect(Match::Encryption::OpenSSL).to receive(:new).with(keychain_name: fake_storage.git_url, working_directory: fake_storage.working_directory).and_return(fake_encryption)
          expect(fake_encryption).to receive(:decrypt_files).and_return(nil)

          spaceship = "spaceship"
          allow(spaceship).to receive(:team_id).and_return("")
          expect(Match::SpaceshipEnsure).to receive(:new).and_return(spaceship)
          expect(spaceship).to receive(:bundle_identifier_exists).and_return(true)

          expect(Match::Utils).to receive(:is_cert_valid?).and_return(false)

          expect do
            Match::Runner.new.run(config)
          end.to raise_error("Your certificate 'Certificate.cer' is not valid, please check end date and renew it if necessary")
        end

        it "skips provisioning profiles when skip_provisioning_profiles set to true", requires_security: true do
          git_url = "https://github.com/fastlane/fastlane/tree/master/certificates"
          values = {
            app_identifier: "tools.fastlane.app",
            type: "appstore",
            git_url: git_url,
            shallow_clone: true,
            username: "flapple@something.com",
            skip_provisioning_profiles: true
          }

          config = FastlaneCore::Configuration.create(Match::Options.available_options, values)
          repo_dir = Dir.mktmpdir
          cert_path = File.join(repo_dir, "something.cer")
          File.copy_stream("./match/spec/fixtures/existing/certs/distribution/Certificate.cer", cert_path)
          openssl = Match::Encryption::OpenSSL.new(
            keychain_name: "login.keychain",
            working_directory: repo_dir
          )
          openssl.encrypt_files(password: ENV.fetch("MATCH_PASSWORD", nil))
          keychain_path = FastlaneCore::Helper.keychain_path("login.keychain") # can be .keychain or .keychain-db
          destination = File.expand_path("~/Library/MobileDevice/Provisioning Profiles/98264c6b-5151-4349-8d0f-66691e48ae35.mobileprovision")

          fake_storage = "fake_storage"
          expect(Match::Storage::GitStorage).to receive(:configure).with(
            git_url: git_url,
            shallow_clone: true,
            skip_docs: false,
            git_branch: "master",
            git_full_name: nil,
            git_user_email: nil,
            clone_branch_directly: false,
            git_basic_authorization: nil,
            git_bearer_authorization: nil,
            git_private_key: nil,
            type: config[:type],
            generate_apple_certs: generate_apple_certs,
            platform: config[:platform],
            google_cloud_bucket_name: "",
            google_cloud_keys_file: "",
            google_cloud_project_id: "",
            skip_google_cloud_account_confirmation: false,
            s3_region: nil,
            s3_access_key: nil,
            s3_secret_access_key: nil,
            s3_bucket: nil,
            s3_object_prefix: nil,
            gitlab_project: nil,
            gitlab_host: 'https://gitlab.com',
            aws_secrets_manager_access_key: nil,
            aws_secrets_manager_force_delete_without_recovery: nil,
            aws_secrets_manager_prefix: nil,
            aws_secrets_manager_path_separator: nil,
            aws_secrets_manager_recovery_window_days: nil,
            aws_secrets_manager_region: nil,
            aws_secrets_manager_secret_access_key: nil,
            readonly: false,
            username: values[:username],
            team_id: nil,
            team_name: nil,
            api_key_path: nil,
            api_key: nil,
            skip_spaceship_ensure: false
          ).and_return(fake_storage)

          expect(fake_storage).to receive(:download).and_return(nil)
          expect(fake_storage).to receive(:clear_changes).and_return(nil)
          allow(fake_storage).to receive(:working_directory).and_return(repo_dir)
          allow(fake_storage).to receive(:prefixed_working_directory).and_return(repo_dir)
          expect(Match::Generator).to receive(:generate_certificate).with(config, :distribution, fake_storage.working_directory, specific_cert_type: nil).and_return(cert_path)
          expect(Match::Generator).to_not(receive(:generate_provisioning_profile))
          expect(FastlaneCore::ProvisioningProfile).to_not(receive(:install))
          expect(fake_storage).to receive(:save_changes!).with(
            files_to_commit: [
              File.join(repo_dir, "something.cer"),
              File.join(repo_dir, "something.p12") # this is important, as a cert consists out of 2 files
            ]
          )

          spaceship = "spaceship"
          allow(spaceship).to receive(:team_id).and_return("")
          expect(Match::SpaceshipEnsure).to receive(:new).and_return(spaceship)
          expect(spaceship).to receive(:certificates_exists).and_return(true)
          expect(spaceship).to_not(receive(:profile_exists))
          expect(spaceship).to receive(:bundle_identifier_exists).and_return(true)

          Match::Runner.new.run(config)
          # Nothing to check after the run
        end
      end
    end

    describe "#device_count_different?" do
      let(:profile_file) { double("profile file") }
      let(:uuid) { "1234-1234-1234-1234" }
      let(:parsed_profile) { { "UUID" => uuid } }
      let(:profile) { double("profile") }
      let(:profile_device) { double("profile_device") }

      before do
        allow(profile).to receive(:uuid).and_return(uuid)
        allow(profile).to receive(:fetch_all_devices).and_return([profile_device])
      end

      it "device is enabled" do
        expect(FastlaneCore::ProvisioningProfile).to receive(:parse).and_return(parsed_profile)
        expect(Spaceship::ConnectAPI::Profile).to receive(:all).and_return([profile])
        expect(Spaceship::ConnectAPI::Device).to receive(:all).and_return([profile_device])

        expect(profile_device).to receive(:device_class).and_return(Spaceship::ConnectAPI::Device::DeviceClass::IPOD)
        expect(profile_device).to receive(:enabled?).and_return(true)

        runner = Match::Runner.new
        expect(runner.device_count_different?(profile: profile_file, platform: :ios)).to be(false)
      end

      it "device is disabled" do
        expect(FastlaneCore::ProvisioningProfile).to receive(:parse).and_return(parsed_profile)
        expect(Spaceship::ConnectAPI::Profile).to receive(:all).and_return([profile])
        expect(Spaceship::ConnectAPI::Device).to receive(:all).and_return([profile_device])

        expect(profile_device).to receive(:device_class).and_return(Spaceship::ConnectAPI::Device::DeviceClass::IPOD)
        expect(profile_device).to receive(:enabled?).and_return(false)

        runner = Match::Runner.new
        expect(runner.device_count_different?(profile: profile_file, platform: :ios)).to be(true)
      end

      it "device is apple silicon mac" do
        expect(FastlaneCore::ProvisioningProfile).to receive(:parse).twice.and_return(parsed_profile)
        expect(Spaceship::ConnectAPI::Profile).to receive(:all).twice.and_return([profile])
        expect(Spaceship::ConnectAPI::Device).to receive(:all).twice.and_return([profile_device])

        expect(profile_device).to receive(:device_class).twice.and_return(Spaceship::ConnectAPI::Device::DeviceClass::APPLE_SILICON_MAC)
        expect(profile_device).to receive(:enabled?).and_return(true)

        runner = Match::Runner.new
        expect(runner.device_count_different?(profile: profile_file, platform: :ios, include_mac_in_profiles: false)).to be(true)
        expect(runner.device_count_different?(profile: profile_file, platform: :ios, include_mac_in_profiles: true)).to be(false)
      end
    end

    describe "#fetch_certificates" do
      it "only fetches certificates which have a private key available" do
        git_url = "https://github.com/fastlane/fastlane/tree/master/certificates"
        values = {
          app_identifier: "tools.fastlane.app",
          type: "appstore",
          git_url: git_url,
          shallow_clone: true,
          username: "flapple@something.com"
        }

        config = FastlaneCore::Configuration.create(Match::Options.available_options, values)
        repo_dir = Dir.mktmpdir
        cert_path = File.join(repo_dir, "something.cer")
        File.copy_stream("./match/spec/fixtures/existing/certs/distribution/Certificate.cer", cert_path)
        openssl = Match::Encryption::OpenSSL.new(
          keychain_name: "login.keychain",
          working_directory: repo_dir
        )
        openssl.encrypt_files(password: ENV.fetch("MATCH_PASSWORD", nil))
        profile_path = "./match/spec/fixtures/test.mobileprovision"
        keychain_path = FastlaneCore::Helper.keychain_path("login.keychain") # can be .keychain or .keychain-db
        destination = File.expand_path("~/Library/MobileDevice/Provisioning Profiles/98264c6b-5151-4349-8d0f-66691e48ae35.mobileprovision")

        fake_storage = "fake_storage"

        allow(fake_storage).to receive(:working_directory).and_return(repo_dir)
        allow(fake_storage).to receive(:prefixed_working_directory).and_return(repo_dir)

        certs_fixtures_dir = File.join(__dir__, "fixtures/existing")
        runner = Match::Runner.new
        allow(runner).to receive(:prefixed_working_directory).and_return(certs_fixtures_dir)

        cert1_path = File.join(certs_fixtures_dir, "certs/distribution/Certificate.cer")
        cert1 = FastlaneCore::Certificate.parse_from_file(cert1_path)
        cert2_path = File.join(certs_fixtures_dir, "certs/distribution/Certificate2.cer")
        cert2 = FastlaneCore::Certificate.parse_from_file(cert2_path)
        expect(runner.fetch_certificates(params: config, working_directory: fake_storage.working_directory)).to eq([cert1, cert2])
      end
    end
  end
end
