IMPORT_INDEX=bazel-out/ios-x86_64-min9.3-applebin_ios-ios_x86_64-dbg/bin/index-store
EXEC_ROOT=$(shell tools/bazelwrapper info execution_root)
DERIVEDDATA=$(shell find ~/Library/Developer/Xcode/DerivedData/ -name FocusXcode-*)

deps:
	tools/bazelwrapper run @rules_pods//:update_pods -- --src_root $$PWD

import:
	index-import -remap "$(EXEC_ROOT)=$(PWD)" $(IMPORT_INDEX) $(DERIVEDDATA)/Index/DataStore 

clean-index:
	rm -rf $(DERIVEDDATA)/Index/DataStore 

disable-indexing:
	defaults write com.apple.dt.XCode IDEIndexDisable 1

enable-indexing:
	defaults write com.apple.dt.XCode IDEIndexDisable 0
