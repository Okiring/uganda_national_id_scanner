#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'national_id_scanner'
  s.version          = '0.1.0'
  s.summary          = 'Native PDF417 scanner for Ugandan National IDs.'
  s.description      = <<-DESC
Native CameraX/AVFoundation + ZXing-C++ PDF417 scanner for Ugandan National IDs.
                       DESC
  s.homepage         = 'https://github.com/uganda/national_id_scanner'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Uganda Scanner' => 'scanner@uganda.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'zxing-cpp', '~> 2.2.0'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
