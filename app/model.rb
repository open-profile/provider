# http://yehudakatz.com/2009/11/12/better-ruby-idioms/

module OpenProfile
  module Server
    module Document
      
      def self.included(base)
        base.send :extend, ClassMethods
      end
      
      def update_created_at
        now = Time.now.utc
        self[:created_at] = now if !persisted? && !created_at?
        #self[:updated_at] = now
      end
      
      module ClassMethods
        def created_at_timestamp!
          key :created_at, Time
          #key :updated_at, Time
          class_eval { before_save :update_created_at }
        end
      end
      
      
    end
  end
end
