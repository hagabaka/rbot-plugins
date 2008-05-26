#-- vim:sw=2:et
#++
#
# :title: Shell Plugin for RBot
#
# Author:: Yaohan Chen <yaohan.chen@gmail.com>
# Copyright:: (C) 2008 Yaohan Chen
# License:: GPLv2


require 'treetop'

Treetop.load_from_string <<END_TREETOP_CODE

grammar Shell
  rule command
    (interpolation / simple)+ {
      def execute(&block)
        yield elements.inject('') {|s, e| s + e.execute(&block)}
      end
    }
  end

  rule interpolation
    '$(' command ')' {
      def execute(&block)
        yield command.execute(&block)
      end
    }
  end

  rule simple
    (!'$(' !')' .)+ {
      def execute(&block)
        text_value
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
      result = tree.execute do |s|
        replies = []
        # FIXME currently all the interpolated commands are created with :from => m,
        # so they are considered depth 1. maybe we should calculate the depth using
        # the command parse tree, but having the parse tree implies finite depth
        new_m = fake_message(s, :from => m, :delegate => false)
        class << new_m
          self
        end.send(:define_method, :reply) do |s|
          replies << s
        end
        @bot.plugins.irc_delegate('privmsg', new_m)
        replies.join(' ')
      end
      m.reply result
    end
  end

  def help(plugin, topic=nil)
    _(%{The "shell" command enables interpolation of commands. For example, "shell say #channel $(ping)" will say the response of the ping command, "pong", in #channel. Note that not all output of commands are considered response, only those using m.reply. It's recommended to interpolate only commands that respond quickly.})
  end
end


plugin = ShellPlugin.new
plugin.map 'shell *command'


