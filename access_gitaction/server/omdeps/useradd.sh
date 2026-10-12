#!/usr/bin/expect -f
set timeout 10
set password [lindex $argv 2]
set host [lindex $argv 0]

spawn ssh root@$host

expect "password"
send "${password}\n"

expect "*"
send "useradd tester2\n"
expect "password"
send "123456\n"
expect "password"
send "123456\n"
expect eof
interact