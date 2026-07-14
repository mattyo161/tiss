#!/usr/bin/env ruby
#
# @description Generate strong random passwords/tokens (ruby SecureRandom)
# @usage tiss mkpass [--len 24] [--count 1] [--hex|--base64|--alnum]
# @example tiss mkpass
# @example tiss mkpass --len 40 --hex --count 5
# @needs ruby
#
# CSPRNG-backed, no clipboard managers, no websites. Default is
# alphanumeric (safe in URLs, shells, and config files); --hex and
# --base64 when a format is required. One per line, so --count pipes.
#
require "securerandom"

len = 24
count = 1
mode = :alnum

ARGV.each_with_index do |a, i|
  case a
  when "-h", "--help", "help"
    warn "usage: tiss mkpass [--len 24] [--count 1] [--hex|--base64|--alnum]"
    exit 0
  when "--len" then len = Integer(ARGV[i + 1])
  when "--count" then count = Integer(ARGV[i + 1])
  when "--hex" then mode = :hex
  when "--base64" then mode = :base64
  when "--alnum" then mode = :alnum
  when /\A--/ then abort "mkpass: unknown argument #{a}"
  end
end

ALNUM = [*"a".."z", *"A".."Z", *"0".."9"].freeze

count.times do
  puts case mode
       when :hex then SecureRandom.hex((len + 1) / 2)[0, len]
       when :base64 then SecureRandom.urlsafe_base64(len)[0, len]
       else Array.new(len) { ALNUM[SecureRandom.random_number(ALNUM.size)] }.join
       end
end
