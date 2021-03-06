#-- vim:sw=2:et
#++
#
# :title: Shell Plugin for RBot
#
# Author:: Yaohan Chen <yaohan.chen@gmail.com>
# Copyright:: (C) 2008 Yaohan Chen
# License:: GPLv2
#
#
# Purpose
#
# This plugin allows interpolation of commands, similar to shells such as bash or sh.
# 
# Examples
#
#   shell say #mychannel $(help)
#   shell say #mychannel $(help $(script echo 'auth'))
#   shell say #mychannel "\$(" and "\)" can be escaped with "\\" (backslash)
#
# Limitations
#
# * Interpolations only work when the command calls m.reply. For example, putting the
#   "say" command inside interpolation does not produce anything
# * Currently there is no attempt to avoid deep recursion


require 'treetop'

Treetop.load_from_string <<'END_TREETOP_CODE'

grammar Shell
  # this grammar accepts commands (strings) containing interpolations, marked by $( )
  # it also provides an algorithm for executing the command with proper interpolation
  
  rule command
    (interpolation / literal)+ {
      # call this on the root of the parse tree
      # the block should accept a string argument which is a command, and return a
      # string which represents its result
      def execute(&block)
        yield elements.inject('') {|s, e| s + e.value(&block)}
      end
    }
  end

  rule interpolation
    open_interpolation command close_interpolation {
      def value(&block)
        command.execute(&block)
      end
    }
  end

  rule open_interpolation
    '$('
  end
  
  rule close_interpolation
    ')'
  end

  rule syntax_token
    open_interpolation / close_interpolation
  end
  
  rule literal
    (escape / plain)+ {
      def value(&block)
        elements.inject('') {|s, e| s + e.value(&block)}
      end
    }
  end
  
  rule plain
    !syntax_token . {
      def value(&block)
        text_value
      end
    }
  end

  # double backslashes actually only stand for singles, because treetop uses \
  # for escaping too
  rule escape
    '\\' content:('\\' / syntax_token / .) {
      def value(&block)
        content.text_value
      end
    }
  end
end

END_TREETOP_CODE


class ShellPlugin < Plugin
  def initialize
    super
    @parser = ShellParser.new
  end

  def shell(m, params)
    tree = @parser.parse(params[:command].to_s)
    unless tree
      m.reply(_('Malformed command %{command}') % {:command => params[:command].to_s})
    else
      result = tree.execute do |cmd|
        replies = []
        # FIXME currently all the interpolated commands are created with :from => m,
        # so they are considered depth 1. maybe we should calculate the depth using
        # the command parse tree, but having the parse tree implies finite depth
        new_m = fake_message(cmd, :from => m, :delegate => false)

        # Override new_m.reply to store replies
        class << new_m
          self
        end.send(:define_method, :reply) do |r|
          replies << r
        end

        # The shell command runs in thread so the handler can (must) run unthreaded
        new_m.in_thread = true

        @bot.plugins.privmsg(new_m)
        replies.join(' ')
      end
      m.reply result unless result.empty?
    end
  end

  def help(plugin, topic=nil)
    _(%{The "shell" command enables interpolation of commands. For example, "shell say #channel $(ping)" will say the response of the ping command, "pong", in #channel. Note that not all output of commands are considered response, only those using m.reply. It's recommended to interpolate only commands that respond quickly.})
  end
end


plugin = ShellPlugin.new
plugin.map 'shell *command', :threaded => true


