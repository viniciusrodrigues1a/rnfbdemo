#!/bin/bash
set -e 

# We need to verify our environment first, so we fail fast for easily detectable things
if [ "$(uname)" == "Darwin" ]; then
  # If the keychain is unlocked then this fails in the middle, let's check that now and fail fast
  if ! security show-keychain-info login.keychain > /dev/null 2>&1; then
    echo "Login keychain is not unlocked, codesigning will fail so macCatalyst build wll fail."
    echo "run 'security unlock-keychain login.keychain' to unlock the login keychain then re-run"
    exit 1
  fi

  # We do not want to run under Rosetta 2, brew doesn't work and compiles might not work after
  arch_name="$(uname -m)"
  if [ "${arch_name}" = "x86_64" ]; then
    if [ "$(sysctl -in sysctl.proc_translated)" = "1" ]; then
      echo "Running on Rosetta 2"
      echo "This is not supported. Run \`env /usr/bin/arch -arm64 /bin/bash --login\` then try again"
      exit 1
    else
      echo "Running on native Intel"
    fi
  elif [ "${arch_name}" = "arm64" ]; then
    echo "Running on ARM"
  else
    echo "Unknown architecture: ${arch_name}"
  fi

  # We need a development team or macCatalyst build will fail
  if [ "$XCODE_DEVELOPMENT_TEAM" == "" ]; then
    printf "\n\n\n\n\n**********************************\n\n\n\n"
    printf "You must set XCODE_DEVELOPMENT_TEAM environment variable to your team id to test macCatalyst"
    printf "Try running it like: XCODE_DEVELOPMENT_TEAM=2W4T123443 ./make-demo.sh (but with your id)"
    printf "Skipping macCatalyst test"
    printf "\n\n\n\n\n**********************************\n\n\n\n"
  fi
fi

# Previous compiles may confound future compiles, erase...
\rm -fr "$HOME/Library/Developer/Xcode/DerivedData/rnfbdemo*"

# Basic template create, rnfb install, link
\rm -fr rnfbdemo

echo "Testing react-native current + react-native-firebase current + Firebase SDKs current"

if ! which yarn > /dev/null 2>&1; then
  echo "This script uses yarn, please install yarn (for example \`npm i yarn -g\` and re-try"
  exit 1
fi

npm_config_yes=true npx @react-native-community/cli init rnfbdemo --skip-install --version=0.69.4
cd rnfbdemo

# New versions of react-native include annoying Ruby stuff that forces use of old rubies. Obliterate.
if [ -f Gemfile ]; then
  rm -f Gemfile* .ruby*
fi

# Now run our initial dependency install
yarn

npm_config_yes=true npx pod-install

# This is the most basic integration
echo "Adding react-native-firebase core app package"
yarn add "@react-native-firebase/app"
echo "Adding basic iOS integration - AppDelegate import and config call"
sed -i -e $'s/AppDelegate.h"/AppDelegate.h"\\\n#import <Firebase.h>/' ios/rnfbdemo/AppDelegate.m*
rm -f ios/rnfbdemo/AppDelegate.m*-e
sed -i -e $'s/RCTBridge \*bridge/if ([FIRApp defaultApp] == nil) { [FIRApp configure]; }\\\n  RCTBridge \*bridge/' ios/rnfbdemo/AppDelegate.m*
rm -f ios/rnfbdemo/AppDelegate.m*-e

# Allow explicit SDK version control by specifying our iOS Pods and Android Firebase Bill of Materials
echo "Adding upstream SDK overrides for precise version control"
#echo "project.ext{set('react-native',[versions:[firebase:[bom:'30.3.2'],],])}" >> android/build.gradle
sed -i -e $'s/  target \'rnfbdemoTests\' do/  $FirebaseSDKVersion = \'9.4.0\'\\\n  target \'rnfbdemoTests\' do/' ios/Podfile
rm -f ios/Podfile??

# This is a reference to a pre-built version of Firestore. It's a neat trick to speed up builds.
# If you are using firestore and database you *may* end up with duplicate symbol build errors referencing "leveldb", the FirebaseFirestoreExcludeLeveldb boolean fixes that.
#sed -i -e $'s/  target \'rnfbdemoTests\' do/  $FirebaseFirestoreExcludeLeveldb = true\\\n  pod \'FirebaseFirestore\', :git => \'https:\\/\\/github.com\\/invertase\\/firestore-ios-sdk-frameworks.git\', :tag => $FirebaseSDKVersion\\\n  target \'rnfbdemoTests\' do/' ios/Podfile
#rm -f ios/Podfile??

# Copy the Firebase config files in - you must supply them
echo "For this demo to work, you must create an \`rnfbdemo\` project in your firebase console,"
echo "then download the android json and iOS plist app definition files to the root directory"
echo "of this repository"

echo "Copying in Firebase android json and iOS plist app definition files downloaded from console"

if [ "$(uname)" == "Darwin" ]; then
  if [ -f "../GoogleService-Info.plist" ]; then
    cp ../GoogleService-Info.plist ios/rnfbdemo/
  else
    echo "Unable to locate the file 'GoogleServices-Info.plist', did you create the firebase project and download the iOS file?"
    exit 1
  fi
fi
if [ -f "../google-services.json" ]; then
  cp ../google-services.json android/app/
else
  echo "Unable to locate the file 'google-services.json', did you create the firebase project and download the android file?"
  exit 1
fi

# Set up python virtual environment so we can do some local mods to Xcode project with mod-pbxproj
# FIXME need to verify that python3 exists (recommend brew) and has venv module installed
if [ "$(uname)" == "Darwin" ]; then
  echo "Setting up python virtual environment + mod-pbxproj for Xcode project edits"
  python3 -m venv virtualenv
  source virtualenv/bin/activate
  pip install pbxproj

  # set PRODUCT_BUNDLE_IDENTIFIER to com.rnfbdemo
  sed -i -e $'s/org.reactjs.native.example/com/' ios/rnfbdemo.xcodeproj/project.pbxproj
  rm -f ios/rnfbdemo.xcodeproj/project.pbxproj-e

  # Add our Google Services file to the Xcode project
  pbxproj file ios/rnfbdemo.xcodeproj rnfbdemo/GoogleService-Info.plist --target rnfbdemo

  # Toggle on iPad: add build flag: TARGETED_DEVICE_FAMILY = "1,2"
  pbxproj flag ios/rnfbdemo.xcodeproj --target rnfbdemo TARGETED_DEVICE_FAMILY "1,2"
fi

# From this point on we are adding optional modules
# First set up all the modules that need no further config for the demo 
echo "Adding packages: Analytics, App Check, Auth, Database, Dynamic Links, Firestore, Functions, In App Messaging, Installations, Messaging, ML, Remote Config, Storage"
yarn add \
  @react-native-firebase/analytics \
  @react-native-firebase/app-check \
  @react-native-firebase/auth \
  @react-native-firebase/database \
  @react-native-firebase/dynamic-links \
  @react-native-firebase/firestore \
  @react-native-firebase/functions \
  @react-native-firebase/in-app-messaging \
  @react-native-firebase/installations \
  @react-native-firebase/messaging \
  @react-native-firebase/remote-config \
  @react-native-firebase/storage

# Crashlytics - repo, classpath, plugin, dependency, import, init
echo "Setting up Crashlytics - package, gradle plugin"
yarn add "@react-native-firebase/crashlytics"


# Performance - classpath, plugin, dependency, import, init
echo "Setting up Performance - package, gradle plugin"
yarn add "@react-native-firebase/perf"

# App Distribution - classpath, plugin, dependency, import, init
echo "Setting up Crashlytics - package, gradle plugin"
yarn add "@react-native-firebase/app-distribution"

# I'm not going to demonstrate messaging and notifications. Everyone gets it wrong because it's hard. 
# You've got to read the docs and test *EVERYTHING* one feature at a time.
# But you have to do a *lot* of work in the AndroidManifest.xml, and make sure your MainActivity *is* the launch intent receiver
# I include it for compile testing only.

echo "Creating default firebase.json (with settings that allow iOS crashlytics to report crashes even in debug mode)"
printf "{\n  \"react-native\": {\n    \"crashlytics_disable_auto_disabler\": true,\n    \"crashlytics_debug_enabled\": true\n  }\n}" > firebase.json

# Copy in our demonstrator App.js
echo "Copying demonstrator App.js"
rm ./App.js && cp ../App.js ./App.js

# Apple builds in general have a problem with architectures on Apple Silicon and Intel, and doing some exclusions should help
sed -i -e $'s/react_native_post_install(installer)/react_native_post_install(installer)\\\n    \\\n    installer.aggregate_targets.each do |aggregate_target|\\\n      aggregate_target.user_project.native_targets.each do |target|\\\n        target.build_configurations.each do |config|\\\n          config.build_settings[\'ONLY_ACTIVE_ARCH\'] = \'YES\'\\\n          config.build_settings[\'EXCLUDED_ARCHS\'] = \'i386\'\\\n        end\\\n      end\\\n      aggregate_target.user_project.save\\\n    end/' ios/Podfile
rm -f ios/Podfile.??

# This is just a speed optimization, very optional, but asks xcodebuild to use clang and clang++ without the fully-qualified path
# That means that you can then make a symlink in your path with clang or clang++ and have it use a different binary
# In that way you can install ccache or buildcache and get much faster compiles...
sed -i -e $'s/react_native_post_install(installer)/react_native_post_install(installer)\\\n    \\\n    installer.pods_project.targets.each do |target|\\\n      target.build_configurations.each do |config|\\\n        config.build_settings["CC"] = "clang"\\\n        config.build_settings["LD"] = "clang"\\\n        config.build_settings["CXX"] = "clang++"\\\n        config.build_settings["LDPLUSPLUS"] = "clang++"\\\n      end\\\n    end/' ios/Podfile
rm -f ios/Podfile??

# This makes the iOS build much quieter. In particular libevent dependency, pulled in by react core / flipper items is ridiculously noisy.
sed -i -e $'s/react_native_post_install(installer)/react_native_post_install(installer)\\\n    \\\n    installer.pods_project.targets.each do |target|\\\n      target.build_configurations.each do |config|\\\n        config.build_settings["GCC_WARN_INHIBIT_ALL_WARNINGS"] = "YES"\\\n      end\\\n    end/' ios/Podfile
rm -f ios/Podfile??

# Static frameworks does not work with flipper (yet) - toggle it off
sed -i -e $'s/FlipperConfiguration.enabled/FlipperConfiguration.disabled/' ios/Podfile
rm -f ios/Podfile.??

# This is how you configure react-native-firebase for static frameworks, required for firebase-ios-sdk v9:
sed -i -e $'s/config = use_native_modules!/config = use_native_modules!\\\n  config = use_frameworks!\\\n  $RNFirebaseAsStaticFramework = true/' ios/Podfile
rm -f ios/Podfile??

# Another workaround needed for static framework build - bitcode will not work with it, but that's okay, bitcode is deprecated
# https://github.com/facebook/react-native/pull/34030#issuecomment-1171197734
sed -i -e $'s/react_native_post_install(installer)/react_native_post_install(installer)\\\n    \\\n    installer.pods_project.targets.each do |target|\\\n      target.build_configurations.each do |config|\\\n        config.build_settings["ENABLE_BITCODE"] = "NO"\\\n      end\\\n    end/' ios/Podfile
rm -f ios/Podfile??

# Another workaround needed for static framework build
# https://github.com/facebook/react-native/issues/31149#issuecomment-800841668
sed -i -e $'s/react_native_post_install(installer)/react_native_post_install(installer)\\\n    installer.pods_project.targets.each do |target|\\\n      if (target.name.eql?(\'FBReactNativeSpec\'))\\\n        target.build_phases.each do |build_phase|\\\n          if (build_phase.respond_to?(:name) \&\& build_phase.name.eql?(\'[CP-User] Generate Specs\'))\\\n            target.build_phases.move(build_phase, 0)\\\n          end\\\n        end\\\n      end\\\n    end/' ios/Podfile
rm -f ios/Podfile.??

# You have to re-run patch-package after yarn since it is not integrated into postinstall, so run it again
echo "Running any patches necessary to compile successfully"
cp -rv ../patches .
npm_config_yes=true npx patch-package

# Run the thing for iOS
if [ "$(uname)" == "Darwin" ]; then

  echo "Installing pods and running iOS app in debug mode"
  npm_config_yes=true npx pod-install

  # Check iOS debug mode compile
  npx react-native run-ios

  # Check iOS release mode compile
  echo "Installing pods and running iOS app in release mode"
  npx react-native run-ios --configuration "Release"

  # Check catalyst build
  if ! [ "$XCODE_DEVELOPMENT_TEAM" == "" ]; then

    echo "Adding macCatalyst entitlements file / build flags to Xcode project"
    cp ../rnfbdemo.entitlements ios/rnfbdemo/
    # add file rnfbdemo/rnfbdemo.entitlements, with reference to rnfbdemo target, but no build phase
    pbxproj file ios/rnfbdemo.xcodeproj rnfbdemo/rnfbdemo.entitlements --target rnfbdemo -C
    # add build flag: CODE_SIGN_ENTITLEMENTS = rnfbdemo/rnfbdemo.entitlements
    pbxproj flag ios/rnfbdemo.xcodeproj --target rnfbdemo CODE_SIGN_ENTITLEMENTS rnfbdemo/rnfbdemo.entitlements
    # add build flag: SUPPORTS_MACCATALYST = YES
    pbxproj flag ios/rnfbdemo.xcodeproj --target rnfbdemo SUPPORTS_MACCATALYST YES
    # add build flag 				DEVELOPMENT_TEAM = 2W4T2B656C;
    pbxproj flag ios/rnfbdemo.xcodeproj --target rnfbdemo DEVELOPMENT_TEAM "$XCODE_DEVELOPMENT_TEAM"
    # add build flag 				DEAD_CODE_STRIPPING = YES;
    pbxproj flag ios/rnfbdemo.xcodeproj --target rnfbdemo DEAD_CODE_STRIPPING YES

    # Add necessary Podfile hack to sign resource bundles for macCatalyst local development
    sed -i -e $'s/react_native_post_install(installer)/react_native_post_install(installer)\\\n    \\\n    installer.pods_project.targets.each do |target|\\\n      if target.respond_to?(:product_type) and target.product_type == "com.apple.product-type.bundle"\\\n        target.build_configurations.each do |config|\\\n          config.build_settings["CODE_SIGN_IDENTITY[sdk=macosx*]"] = "-"\\\n        end\\\n      end\\\n    end/' ios/Podfile
    rm -f ios/Podfile-e

    # macCatalyst requires one extra path on linker line: '$(SDKROOT)/System/iOSSupport/usr/lib/swift'
    sed -i -e $'s/react_native_post_install(installer)/react_native_post_install(installer)\\\n    \\\n    installer.aggregate_targets.each do |aggregate_target|\\\n      aggregate_target.user_project.native_targets.each do |target|\\\n        target.build_configurations.each do |config|\\\n          config.build_settings[\'LIBRARY_SEARCH_PATHS\'] = [\'$(SDKROOT)\/usr\/lib\/swift\', \'$(SDKROOT)\/System\/iOSSupport\/usr\/lib\/swift\', \'$(inherited)\']\\\n        end\\\n      end\\\n      aggregate_target.user_project.save\\\n    end/' ios/Podfile
    rm -f ios/Podfile.??

    echo "Installing pods and running iOS app in macCatalyst mode"
    npm_config_yes=true npx pod-install

    # Now run it with our mac device name as device target, that triggers catalyst build
    # Need to check if the development team id is valid? error 70 indicates team not added as account / cert not present / xcode does not have access to keychain?

    # For some reason, the device id returned if you use the computer name is wrong.
    # It is also wrong from ios-deploy or xcrun xctrace list devices
    # The only way I have found to get the right ID is to provide the wrong one then parse out the available one
    CATALYST_DESTINATION=$(xcodebuild -workspace ios/rnfbdemo.xcworkspace -configuration Debug -scheme rnfbdemo -destination id=7153382A-C92B-5798-BEA3-D82D195F25F8 2>&1|grep macOS|grep Catalyst|head -1 |cut -d':' -f5 |cut -d' ' -f1)

    # WIP This requires a CLI patch to the iOS platform to accept a UDID it cannot probe, and to set type to catalyst
    npx react-native run-ios --udid "$CATALYST_DESTINATION"
  fi
fi

# If we are on WSL the user needs to now run it from the Windows side
# Getting it to run from WSL is a real mess (it is possible, but not recommended)
# So we will stop now that we've done all the installation and file editing
if [ "$(uname -a | grep Linux | grep -c microsoft)" == "1" ]; then
  echo "Detected Windows Subsystem for Linux. Stopping now."

  # Clear out the unix-y node_modules
  \rm -fr node_modules
  echo "To run the app use Windows Powershell in the rnfbdemo directory with these commands:"
  echo "npm i"
  echo "npx react-native run-android"
  exit
fi
