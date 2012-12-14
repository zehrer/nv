Pod::Spec.new do |s|
  s.name                  = "Rebel"
  s.version               = "0.2"
  s.summary               = "Cocoa framework for improving AppKit."

  s.homepage              = "https://github.com/github/Rebel"
  s.license               = 'MIT'
  s.author                = { "GitHub" => "support@github.com" }

  s.source                = { :git => "https://github.com/github/Rebel.git", :branch => "master" }
  s.source_files          = 'Rebel'
  s.framework             = 'AppKit'

  s.platform              = :osx
  s.osx.deployment_target = '10.7'
  s.requires_arc          = true

  s.dependency              'libextobjc/EXTKeyPathCoding'

  def s.post_install(target_installer)
    project = target_installer.project
    project.objects.each do |obj|
      if obj.isa.to_s == "PBXBuildFile"
        fileRef = obj.to_plist["fileRef"]
        file = project.files.select { |obj| obj.uuid == fileRef }[0]
        file_name = file.pathname.basename.to_s
        if ["NSColor+RBLCGColorAdditions.m"].include?(file_name)
          obj.settings.delete('COMPILER_FLAGS')
        end
      end
    end
  end
end
