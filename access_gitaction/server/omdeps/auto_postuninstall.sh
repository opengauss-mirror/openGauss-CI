#!/usr/bin/expect -f
set timeout -1
set username [lindex $argv 0]
set usergroup [lindex $argv 1]
set xmlpath [lindex $argv 2]
set envpath [lindex $argv 3]
set scriptpath [lindex $argv 4]
set password [lindex $argv 5]

#spawn $scriptpath/gs_postuninstall -U ${username} -X ${xmlpath} --delete-user
spawn $scriptpath/gs_postuninstall -U ${username} -X ${xmlpath} --delete-user 
expect {
"yes/no" {send "yes\n"}
}

expect {
"Password*" {send "${password}\n"}
}

expect eof
interact

