# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    # @private
    class ResetCounters < DataMigration
      attr_reader :model, :counters, :touch

      def initialize(model_name, counters, options = {})
        @model = Object.const_get(model_name, false)
        @counters = counters
        @touch = options[:touch]
      end

      def collection
        model.unscoped.in_batches(of: 100)
      end

      def process(relation)
        updates = counters.map do |counter_association|
          has_many_association = has_many_association(counter_association)

          foreign_key  = has_many_association.foreign_key.to_s
          child_class  = has_many_association.klass
          reflection   = child_class._reflections.values.find { |e| e.belongs_to? && e.foreign_key.to_s == foreign_key && e.options[:counter_cache].present? }
          counter_name = reflection.counter_cache_column

          quoted_association_table = connection.quote_table_name(has_many_association.table_name)
          count_subquery = <<~SQL
            SELECT COUNT(*)
            FROM #{quoted_association_table}
            WHERE #{quoted_association_table}.#{connection.quote_column_name(foreign_key)} =
              #{model.quoted_table_name}.#{model.quoted_primary_key}
          SQL

          "#{connection.quote_column_name(counter_name)} = (#{count_subquery})"
        end

        if touch
          names = touch if touch != true
          names = Array.wrap(names)
          options = names.extract_options!
          touch_updates = touch_attributes_with_time(*names, **options)
          updates << model.sanitize_sql_for_assignment(touch_updates)
        end

        relation.update_all(updates.join(", "))
      end

      def count
        # Exact counts are expensive on large tables, since PostgreSQL
        # needs to do a full scan. An estimated count should give a pretty decent
        # approximation of rows count in this case.
        Utils.estimated_count(connection, model.table_name)
      end

      private
        def has_many_association(counter_association) # rubocop:disable Naming/PredicateName
          has_many_association = model.reflect_on_association(counter_association)

          if !has_many_association
            has_many = model.reflect_on_all_associations(:has_many)

            has_many_association = has_many.find do |association|
              counter_cache_column = association.counter_cache_column
              counter_cache_column && counter_cache_column.to_sym == counter_association.to_sym
            end

            counter_association = has_many_association.plural_name if has_many_association
          end
          raise ArgumentError, "'#{model.name}' has no association called '#{counter_association}'" if !has_many_association

          if has_many_association.is_a?(ActiveRecord::Reflection::ThroughReflection)
            has_many_association = has_many_association.through_reflection
          end

          has_many_association
        end

        def touch_attributes_with_time(*names, time: nil)
          attribute_names = timestamp_attributes_for_update & model.column_names
          attribute_names |= names.map(&:to_s)
          attribute_names.index_with(time || Time.current)
        end

        def timestamp_attributes_for_update
          ["updated_at", "updated_on"].map { |name| model.attribute_aliases[name] || name }
        end

        def connection
          model.connection
        end
    end
  end
end
