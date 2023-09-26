# frozen_string_literal: true

module OnlineMigrations
  # @private
  module CommandRecorder
    REVERSIBLE_AND_IRREVERSIBLE_METHODS = [
      :update_column_in_batches,
      :initialize_column_rename,
      :initialize_columns_rename,
      :revert_initialize_column_rename,
      :revert_initialize_columns_rename,
      :finalize_column_rename,
      :finalize_columns_rename,
      :revert_finalize_column_rename,
      :revert_finalize_columns_rename,
      :initialize_table_rename,
      :revert_initialize_table_rename,
      :finalize_table_rename,
      :revert_finalize_table_rename,
      :swap_column_names,
      :add_column_with_default,
      :add_not_null_constraint,
      :remove_not_null_constraint,
      :add_text_limit_constraint,
      :remove_text_limit_constraint,
      :add_reference_concurrently,
      :change_column_type_in_background,
      :enqueue_background_migration,

      # column type change helpers
      :initialize_column_type_change,
      :initialize_columns_type_change,
      :revert_initialize_column_type_change,
      :revert_initialize_columns_type_change,
      :backfill_column_for_type_change,
      :backfill_columns_for_type_change,
      :finalize_column_type_change,
      :finalize_columns_type_change,
      :revert_finalize_column_type_change,
      :cleanup_column_type_change,
      :cleanup_columns_type_change,
    ]

    REVERSIBLE_AND_IRREVERSIBLE_METHODS.each do |method|
      class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{method}(*args, &block)          # def create_table(*args, &block)
          record(:"#{method}", args, &block)  #   record(:create_table, args, &block)
        end                                   # end
      RUBY
      ruby2_keywords(method) if respond_to?(:ruby2_keywords, true)
    end

    private
      module StraightReversions
        {
          initialize_column_rename:           :revert_initialize_column_rename,
          initialize_columns_rename:          :revert_initialize_columns_rename,
          finalize_column_rename:             :revert_finalize_column_rename,
          finalize_columns_rename:            :revert_finalize_columns_rename,
          initialize_table_rename:            :revert_initialize_table_rename,
          finalize_table_rename:              :revert_finalize_table_rename,
          add_not_null_constraint:            :remove_not_null_constraint,
          initialize_column_type_change:      :revert_initialize_column_type_change,
          initialize_columns_type_change:     :revert_initialize_columns_type_change,
          finalize_column_type_change:        :revert_finalize_column_type_change,
          finalize_columns_type_change:       :revert_finalize_columns_type_change,
        }.each do |cmd, inv|
          [[inv, cmd], [cmd, inv]].each do |method, inverse|
            class_eval <<-RUBY, __FILE__, __LINE__ + 1
              def invert_#{method}(args, &block)    # def invert_create_table(args, &block)
                [:#{inverse}, args, block]          #   [:drop_table, args, block]
              end                                   # end
            RUBY
          end
        end
      end

      include StraightReversions

      def invert_swap_column_names(args)
        table_name, column1, column2 = args
        [:swap_column_names, [table_name, column2, column1]]
      end

      def invert_add_column_with_default(args)
        table_name, column_name, = args
        [:remove_column, [table_name, column_name]]
      end

      def invert_revert_initialize_column_rename(args)
        _table, column, new_column = args
        if !column || !new_column
          raise ActiveRecord::IrreversibleMigration,
            "revert_initialize_column_rename is only reversible if given a column and new_column."
        end
        [:initialize_column_rename, args]
      end

      def invert_revert_initialize_columns_rename(args)
        _table, old_new_column_hash = args
        if !old_new_column_hash
          raise ActiveRecord::IrreversibleMigration,
            "revert_initialize_columns_rename is only reversible if given a hash of old and new columns."
        end
        [:initialize_columns_rename, args]
      end

      def invert_finalize_table_rename(args)
        _table_name, new_name = args
        if !new_name
          raise ActiveRecord::IrreversibleMigration,
            "finalize_table_rename is only reversible if given a new_name."
        end
        [:revert_finalize_table_rename, args]
      end

      def invert_revert_initialize_column_type_change(args)
        if !args[2]
          raise ActiveRecord::IrreversibleMigration,
            "revert_initialize_column_type_change is only reversible if given a new_type."
        end
        super
      end

      def invert_revert_initialize_columns_type_change(args)
        if args[1].empty?
          raise ActiveRecord::IrreversibleMigration,
            "revert_initialize_columns_type_change is only reversible if given a columns_and_types."
        end
        super
      end

      def invert_add_not_null_constraint(args)
        args.last.delete(:validate) if args.last.is_a?(Hash)
        [:remove_not_null_constraint, args]
      end

      def invert_add_text_limit_constraint(args)
        args.last.delete(:validate) if args.last.is_a?(Hash)
        [:remove_text_limit_constraint, args]
      end

      def invert_remove_text_limit_constraint(args)
        if !args[2]
          raise ActiveRecord::IrreversibleMigration, "remove_text_limit_constraint is only reversible if given a limit."
        end

        [:add_text_limit_constraint, args]
      end
  end
end
