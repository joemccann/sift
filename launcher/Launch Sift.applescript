set appBundlePath to POSIX path of (path to me)
set launcherDir to do shell script "/usr/bin/dirname " & quoted form of appBundlePath
set repoDir to do shell script "/usr/bin/dirname " & quoted form of launcherDir
set runnerPath to repoDir & "/scripts/build_and_launch_local_app.sh"

try
	set logPath to do shell script "/bin/zsh " & quoted form of runnerPath
	display notification "Sift launched." with title "Sift"
on error errMsg number errNum
	display dialog "Sift failed to build or launch." & return & return & errMsg buttons {"OK"} default button "OK" with icon stop
end try
