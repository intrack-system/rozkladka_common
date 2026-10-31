#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint rozkladka_common.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'rozkladka_common'
  s.version          = '0.1.0'
  s.summary          = 'Ключ телефона для активації з InTrack.'
  s.description      = <<-DESC
Ключ телефона ECDSA P-256 у Secure Enclave.
                       DESC
  s.homepage         = 'https://github.com/intrack-system/rozkladka_common'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Любомир Фальфушинський' => '' }
  s.source           = { :path => '.' }
  s.source_files = 'rozkladka_common/Sources/rozkladka_common/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'rozkladka_common_privacy' => ['rozkladka_common/Sources/rozkladka_common/PrivacyInfo.xcprivacy']}
end
