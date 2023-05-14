require 'zlib'
require 'base64'
require "aws-sdk-secretsmanager"

aws_sm_client = Aws::SecretsManager::Client.new(region: 'us-west-2')
retrieved_secret = aws_sm_client.get_secret_value({
                                                    secret_id: 'fastlane.andmatch.com.jigx.benefit_point.android/release.keystore'
                                                  })
decoded_secret = Zlib::Inflate.inflate(Base64.decode64(retrieved_secret.secret_binary))
File.open('release.keystore', 'w') { |file| file.puts(decoded_secret) }
