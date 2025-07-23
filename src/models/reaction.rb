# frozen_string_literal: true

module ZCA
  module Models
    module Reactions
      HEART = '/-heart'
      LIKE = '/-strong'
      HAHA = ':>'
      WOW = ':o'
      CRY = ':-(( '
      ANGRY = ':-h'
      KISS = ':-*'
      TEARS_OF_JOY = ":')"
      SHIT = '/-shit'
      ROSE = '/-rose'
      BROKEN_HEART = '/-break'
      DISLIKE = '/-weak'
      LOVE = ';xx'
      CONFUSED = ';-/'
      WINK = ';-)'
      FADE = '/-fade'
      SUN = '/-li'
      BIRTHDAY = '/-bd'
      BOMB = '/-bome'
      OK = '/-ok'
      PEACE = '/-v'
      THANKS = '/-thanks'
      PUNCH = '/-punch'
      SHARE = '/-share'
      PRAY = '_()_'
      NO = '/-no'
      BAD = '/-bad'
      LOVE_YOU = '/-loveu'
      SAD = '--b'
      VERY_SAD = ':(('
      COOL = 'x-)'
      NERD = '8-)'
      BIG_SMILE = ';-d'
      SUNGLASSES = 'b-)'
      NEUTRAL = ':--|'
      SAD_FACE = 'p-('
      BYE = ':-bye'
      SLEEPY = '|-)'
      WIPE = ':wipe'
      DIG = ':-dig'
      ANGUISH = '&-('
      HANDCLAP = ':handclap'
      ANGRY_FACE = '>-|'
      F_CHAIR = ':-f'
      L_CHAIR = ':-l'
      R_CHAIR = ':-r'
      SILENT = ';-x'
      SURPRISE = ':-o'
      EMBARRASSED = ';-s'
      AFRAID = ';-a'
      SAD2 = ':-<'
      BIG_LAUGH = ':))'
      RICH = '$-)' 
      BEER = '/-beer'
      NONE = ''
    end

    TReactionContent = Struct.new(:r_msg, :r_icon, :r_type, :source, keyword_init: true)
    TReaction = Struct.new(
      :action_id, :msg_id, :cli_msg_id, :msg_type, :uid_from, :id_to, :d_name, :content, :ts, :ttl,
      keyword_init: true
    )

    class Reaction
      attr_reader :data, :thread_id, :is_self, :is_group
      def initialize(uid, data, is_group)
        @data = data
        @thread_id = is_group || data.uid_from == '0' ? data.id_to : data.uid_from
        @is_self = data.uid_from == '0'
        @is_group = is_group
        data.id_to = uid if data.id_to == '0'
        data.uid_from = uid if data.uid_from == '0'
      end
    end
  end
end 