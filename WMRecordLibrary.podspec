pod::Spec.new do |s|
  s.name         = 'VideoRecord'
  s.version      = '0.0.1'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.homepage     = 'https://github.com/WangMing1998/videoRecordFramework'
  s.author       = { 'WangMing' => '286241793@qq.com' }
  s.summary      = 'AVFoundtatino videoRecord'
  s.framework    = 'UIKit','Foundation','AVFoundation','CoreMedia','Photos','CoreGraphics'

  s.platform     =  :ios, '7.0'
  s.source       =  { :git => 'https://github.com/WangMing1998/videoRecordFramework.git', :tag => s.version}
  s.source_files = 'WMRecordLibrary/*.{h,m}'
  s.requires_arc = true

# Pod Dependencies
#  s.subspec 'SDWebImage' do |sds|
#    sds.dependency 'SDWebImage', '>= 3.7.6'

end


