module Mongoid::TaggableWithContext
  extend ActiveSupport::Concern

  class AggregationStrategyMissing < Exception; end

  included do
    class_attribute :taggable_with_context_options
    self.taggable_with_context_options = {}
    delegate "convert_string_to_array",     :to => 'self.class'
    delegate "convert_array_to_string",     :to => 'self.class'
    delegate "convert_string_to_slugs",     :to => 'self.class'
    delegate "convert_array_to_slug_array", :to => 'self.class'
    delegate "filter_tags",                  :to => 'self.class'
    delegate "get_tag_separator_for",       :to => 'self.class'
    delegate "tag_contexts",                :to => 'self.class'
    delegate "tag_options_for",             :to => 'self.class'
  end

  module ClassMethods
    # Macro to declare a document class as taggable, specify field name
    # for tags, and set options for tagging behavior.
    #
    # @example Define a taggable document.
    #
    #   class Article
    #     include Mongoid::Document
    #     include Mongoid::Taggable
    #     taggable :keywords, :separator => ' ', :aggregation => true, :default_type => "seo"
    #   end
    #
    # @param [ Symbol ] field The name of the field for tags.
    # @param [ Hash ] options Options for taggable behavior.
    #
    # @option options [ String ] :separator The tag separator to
    #   convert from; defaults to ','
    # @option options [ true, false ] :aggregation Whether or not to
    #   aggregate counts of tags within the document collection using
    #   map/reduce; defaults to false
    # @option options [ String ] :default_type The default type of the tag.
    #   Each tag can optionally have a tag type. The default type is nil
    def taggable(*args)
      # init variables
      options = args.extract_options!
      tags_field = (args.blank? ? :tags : args.shift).to_sym
      options.reverse_merge!(
        :separator => ' ',
        :array_field => "#{tags_field}_array".to_sym,
        :slug_field => "#{tags_field}_slug".to_sym
      )
      tags_array_field = options[:array_field]
      tags_slug_array_field = options[:slug_field]

      # register / update settings
      class_options = taggable_with_context_options || {}
      class_options[tags_field] = options
      self.taggable_with_context_options = class_options

      # setup fields & indexes
      field tags_field, :default => ""
      field tags_array_field, :type => Array, :default => []
      field tags_slug_array_field, :type => Array, :default => []
      index tags_array_field, tags_slug_array_field

      # singleton methods
      class_eval <<-END
        class << self
          def #{tags_field}
            tags_for(:"#{tags_field}")
          end

          def #{tags_field}_with_weight
            tags_with_weight_for(:"#{tags_field}")
          end

          def #{tags_field}_separator
            get_tag_separator_for(:"#{tags_field}")
          end

          def #{tags_field}_separator=(value)
            set_tag_separator_for(:"#{tags_field}", value)
          end

          def #{tags_field}_tagged_with(tags)
            tagged_with(:"#{tags_field}", tags)
          end
        end
      END

      # instance methods
      class_eval <<-END
        def #{tags_field}=(s)
          s = filter_tags(s)
          super
          write_attribute(:#{tags_array_field}, convert_string_to_array(s, get_tag_separator_for(:"#{tags_field}")))
          write_attribute(:#{tags_slug_array_field}, convert_string_to_slugs(s, get_tag_separator_for(:"#{tags_field}")))
        end

        def #{tags_array_field}=(a)
          super
          write_attribute(:#{tags_field}, convert_array_to_string(a, get_tag_separator_for(:"#{tags_field}")))
        end

        def #{tags_slug_array_field}=(a)
          super
          write_attribute(:#{tags_slug_array_field}, convert_array_to_slug_array(a, get_tag_separator_for(:"#{tags_field}")))
        end
      END
    end

    def tag_contexts
      self.taggable_with_context_options.keys
    end

    def tag_options_for(context)
      self.taggable_with_context_options[context]
    end

    def tags_for(context, conditions={})
      raise AggregationStrategyMissing
    end

    def tags_with_weight_for(context, conditions={})
      raise AggregationStrategyMissing
    end

    def get_tag_separator_for(context)
      self.taggable_with_context_options[context][:separator]
    end

    def set_tag_separator_for(context, value)
      self.taggable_with_context_options[context][:separator] = value.nil? ? " " : value.to_s
    end

    # Find documents tagged with all tags passed as a parameter, given
    # as an Array or a String using the configured separator.
    #
    # @example Find matching all tags in an Array.
    #   Article.tagged_with(['ruby', 'mongodb'])
    # @example Find matching all tags in a String.
    #   Article.tagged_with('ruby, mongodb')
    #
    # @param [ String ] :field The field name of the tag.
    # @param [ Array<String, Symbol>, String ] :tags Tags to match.
    # @return [ Criteria ] A new criteria.
    def tagged_with(context, tags)
      tags = convert_string_to_array(tags, get_tag_separator_for(context)) if tags.is_a? String
      array_field = tag_options_for(context)[:array_field]
      all_in(array_field => tags)
    end

    # Helper method to convert a String to an Array based on the
    # configured tag separator.
    def convert_string_to_array(str = "", seperator = " ")
      str.split(seperator).map(&:strip).uniq.compact
    end

    def convert_array_to_string(ary = [], seperator = " ")
      ary.uniq.compact.join(seperator)
    end

    def convert_array_to_slug_array(ary = [], seperator = " ")
      ary.uniq.compact.collect{|tag| tag.to_url}
    end

    def convert_string_to_slugs(str = "", seperator = " ")
      str.split(seperator).map(&:url_encode).uniq.compact
    end

    def filter_tags(str = "")
      a = []
      a = str.split(',').map{|x| x.split(' ')}
      a.flatten!
      a.collect!{ |tag| tag.gsub(/([^a-z0-9\/'"]+)/i, ' ').strip.singularize.downcase}
      a.map!{|x| x.split(' ')}
      a.flatten!
      a.delete_if{|x| x.size < 4}
      a.uniq!
      #a.compact!
      a = a - stop_words
      a.join(',')
    end

    def stop_words
      words = ["a", "a's", "able", "about", "above",
        "according", "accordingly", "across", "actually", "after", "afterwards",
        "again", "against", "ain't", "all", "allow", "allows", "almost",
        "alone","along", "already", "also", "although", "always", "am", "among",
        "amongst", "an", "and", "another", "any", "anybody", "anyhow", "anyone",
        "anything", "anyway", "anyways", "anywhere", "apart", "appear", "appreciate",
        "appropriate", "are", "aren't", "around", "as", "aside", "ask", "asking",
        "associated", "at", "available", "away", "awfully", "be", "became", "because",
        "become", "becomes", "becoming", "been", "before", "beforehand", "behind",
        "being", "believe", "below", "beside", "besides", "best", "better", "between",
        "beyond", "both", "brief", "but", "by", "c'mon", "c's", "came", "can", "can't",
        "cannot", "cant", "cause", "causes", "certain", "certainly", "changes",
        "clearly", "co", "com", "come", "comes", "concerning", "consequently",
        "consider", "considering", "contain", "containing", "contains", "corresponding",
        "could", "couldn't", "course", "currently", "definitely", "described",
        "despite", "did", "didn't", "different", "do", "does", "doesn't", "doing",
        "don't", "done", "down", "downwards", "during", "each", "edu", "eg", "eight",
        "either", "else", "elsewhere", "enough", "entirely", "especially", "et", "etc",
        "even", "ever", "every", "everybody", "everyone", "everything", "everywhere",
        "ex", "exactly", "example", "except", "far", "few", "fifth", "first", "five",
        "followed", "following", "follows", "for", "former", "formerly", "forth",
        "four", "from", "further", "furthermore", "get", "gets", "getting", "given",
        "gives", "go", "goes", "going", "gone", "got", "gotten", "greetings", "had",
        "hadn't", "happens", "hardly", "has", "hasn't", "have", "haven't", "having",
        "he", "he's", "hello", "help", "hence", "her", "here", "here's", "hereafter",
        "hereby", "herein", "hereupon", "hers", "herself", "hi", "him", "himself",
        "his", "hither", "hopefully", "how", "howbeit", "however", "i'd", "i'll", "i'm",
        "i've", "ie", "if", "ignored", "immediate", "in", "inasmuch", "inc", "indeed",
        "indicate", "indicated", "indicates", "inner", "insofar", "instead", "into",
        "inward", "is", "isn't", "it", "it'd", "it'll", "it's", "its", "itself", "just",
        "keep", "keeps", "kept", "know", "knows", "known", "last", "lately", "later",
        "latter", "latterly", "least", "less", "lest", "let", "let's", "like", "liked",
        "likely", "little", "look", "looking", "looks", "ltd", "mainly", "many", "may",
        "maybe", "me", "mean", "meanwhile", "merely", "might", "more", "moreover",
        "most", "mostly", "much", "must", "my", "myself", "name", "namely", "nd",
        "near", "nearly", "necessary", "need", "needs", "neither", "never",
        "nevertheless", "new", "next", "nine", "no", "nobody", "non", "none", "noone",
        "nor", "normally", "not", "nothing", "novel", "now", "nowhere", "obviously",
        "of", "off", "often", "oh", "ok", "okay", "old", "on", "once", "one", "ones",
        "only", "onto", "or", "other", "others", "otherwise", "ought", "our", "ours",
        "ourselves", "out", "outside", "over", "overall", "own", "particular",
        "particularly", "per", "perhaps", "placed", "please", "plus", "possible",
        "presumably", "probably", "provides", "que", "quite", "qv", "rather", "rd",
        "re", "really", "reasonably", "regarding", "regardless", "regards",
        "relatively", "respectively", "right", "said", "same", "saw", "say", "saying",
        "says", "second", "secondly", "see", "seeing", "seem", "seemed", "seeming",
        "seems", "seen", "self", "selves", "sensible", "sent", "serious", "seriously",
        "seven", "several", "shall", "she", "should", "shouldn't", "since", "six", "so",
        "some", "somebody", "somehow", "someone", "something", "sometime", "sometimes",
        "somewhat", "somewhere", "soon", "sorry", "specified", "specify", "specifying",
        "still", "sub", "such", "sup", "sure", "t's", "take", "taken", "tell", "tends",
        "th", "than", "thank", "thanks", "thanx", "that", "that's", "thats", "the",
        "their", "theirs", "them", "themselves", "then", "thence", "there", "there's",
        "thereafter", "thereby", "therefore", "therein", "theres", "thereupon", "these",
        "they", "they'd", "they'll", "they're", "they've", "think", "third", "this",
        "thorough", "thoroughly", "those", "though", "three", "through", "throughout",
        "thru", "thus", "to", "together", "too", "took", "toward", "towards", "tried",
        "tries", "truly", "try", "trying", "twice", "two", "un", "under",
        "unfortunately", "unless", "unlikely", "until", "unto", "up", "upon", "us",
        "use", "used", "useful", "uses", "using", "usually", "value", "various", "very",
        "via", "viz", "vs", "want", "wants", "was", "wasn't", "way", "we", "we'd",
        "we'll", "we're", "we've", "welcome", "well", "went", "were", "weren't", "what",
        "what's", "whatever", "when", "whence", "whenever", "where", "where's",
        "whereafter", "whereas", "whereby", "wherein", "whereupon", "wherever",
        "whether", "which", "while", "whither", "who", "who's", "whoever", "whole",
        "whom", "whose", "why", "will", "willing", "wish", "with", "within", "without",
        "won't", "wonder", "would", "wouldn't", "yes", "yet", "you", "you'd", "you'll",
        "you're", "you've", "your", "yours", "yourself", "yourselves", "zero", "crap",
        "post", "reported", "question", "good", "problem", "site", "needed", "neolitic",
        "spam", "forum", "dont", "great", "thread", "talk", "newbie"]
    end
  end
end
