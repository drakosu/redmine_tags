class ActsAsTaggableMigration < ActiveRecord::Migration
  def up

    create_table :rtag_dummy  # dummy table for recording migration actions.

    # ActsAsTaggableOnMigration
    unless table_exists?(:tags)
      create_table :tags do |t|
        t.string :name
      end

      create_table :taggings do |t|
        t.references :tag
        t.references :taggable, polymorphic: true
        t.references :tagger, polymorphic: true
        # Limit is created to prevent MySQL error on index
        # length for MyISAM table type: http://bit.ly/vgW2Ql
        t.string :context, limit: 128
        t.datetime :created_at
      end

      add_index :taggings, :tag_id
      add_index :taggings, [:taggable_id, :taggable_type, :context]
      add_column :rtag_dummy, :table_created_by_rtag, :integer
    end

    # redmine_crm skips some collumns when creating the taggings table
    unless column_exists?(:taggings, :context)
      add_column :taggings, :context, :string, limit: 128
      add_column :rtag_dummy, :column_context_added_by_rtag, :integer
    end

    unless column_exists?(:taggings, :tagger_id)
      change_table :taggings do |t|
        t.references :tagger, polymorphic: true
      end
      add_column :rtag_dummy, :reference_tagger_added_by_rtag, :integer
    end

    # AddMissingUniqueIndices
    unless column_exists?(:tags, :taggings_count)
      # redmine_crm skips the following indexes so we have to check their exitance
      unless index_exists?(:tags, :name)
        add_index :tags, :name, unique: true
        add_column :rtag_dummy, :index_name_added_by_rtag, :integer
      end

      if index_exists?(:taggings, :tag_id)
        remove_index :taggings, :tag_id
        add_column :rtag_dummy, :index_tag_id_removed_by_rtag, :integer
      end

      if index_exists?(:taggings, [:taggable_id, :taggable_type, :context])
        remove_index :taggings, [:taggable_id, :taggable_type, :context]
      end

      add_index(
        :taggings,
        [
          :tag_id,
          :taggable_id,
          :taggable_type,
          :context,
          :tagger_id,
          :tagger_type
        ],
        unique: true, name: 'taggings_idx'
      )
      add_column :rtag_dummy, :index_taggings_idx_added_by_rtag, :integer

      # AddTaggingsCounterCacheToTags
      add_column :tags, :taggings_count, :integer, default: 0
      add_column :rtag_dummy, :column_taggings_count_added_by_rtag, :integer
      ActsAsTaggableOn::Tag.reset_column_information
      ActsAsTaggableOn::Tag.find_each do |tag|
        ActsAsTaggableOn::Tag.reset_counters(tag.id, :taggings)
      end

      # AddMissingTaggableIndex
      add_index :taggings, [:taggable_id, :taggable_type, :context]

      # ChangeCollationForTagNames
      if ActsAsTaggableOn::Utils.using_mysql?
        execute(
          'ALTER TABLE tags MODIFY name varchar(255) CHARACTER SET utf8 COLLATE utf8_bin;'
        )
      end
    end

    # AddMissingIndexes
    unless index_exists?(:taggings, :tag_id)
      add_index :taggings, :tag_id
      add_index :taggings, :taggable_id
      add_index :taggings, :taggable_type
      add_index :taggings, :tagger_id
      add_index :taggings, :context
      add_index :taggings, [:tagger_id, :tagger_type]
      add_index(
        :taggings,
        [:taggable_id, :taggable_type, :tagger_id, :context],
        name: 'taggings_idy'
      )
      add_column :rtag_dummy, :index_taggings_idy_added_by_rtag, :integer
    end
  end

  def down

    if (ENV['FORCE_REDMINE_TAGS_TABLES_REMOVAL'] == 'yes') || column_exists?(:rtag_dummy, :table_created_by_rtag)
      drop_table :taggings
      drop_table :tags
    else
      puts '********' * 10
      puts 'WARNING: This will revert changes to the `tags` and `taggings` tabels'
      puts 'If you want to remove them, run the command ' \
        'supplying the `FORCE_REDMINE_TAGS_TABLES_REMOVAL=yes` variable.'
      puts '********' * 10

      if column_exists?(:rtag_dummy, :column_context_added_by_rtag) and column_exists?(:taggings, :context)
        remove_column :taggings, :context, :string, limit: 128
      end
  
      if column_exists?(:rtag_dummy, :reference_tagger_added_by_rtag) and column_exists?(:taggings, :tagger)
        remove_reference :taggings, :tagger, polymorphic: true
      end
  
      if column_exists?(:rtag_dummy, :index_name_added_by_rtag) and index_exists?(:tags, :name)
        remove_index :tags, :name
      end

      if column_exists?(:rtag_dummy, :index_tag_id_removed_by_rtag) and !index_exists?(:taggings, :tag_id)
        add_index :taggings, :tag_id
      end

      if column_exists?(:rtag_dummy, :index_taggings_idx_added_by_rtag) and index_name_exists?(:taggings, 'taggings_idx', default = nil)
        remove_index :taggings, name: 'taggings_idx'
      end

      if column_exists?(:rtag_dummy, :column_taggings_count_added_by_rtag) and column_exists?(:tags, :taggings_count)
        remove_column :tags, :taggings_count
      end

      if column_exists?(:rtag_dummy, :index_taggings_idy_added_by_rtag) and index_exists?(:taggings, :tag_id)
        remove_index :taggings, name: 'taggings_idy'
        remove_index :taggings, [:tagger_id, :tagger_type]
        remove_index :taggings, :context
        remove_index :taggings, :tagger_id
        remove_index :taggings, :taggable_type
        remove_index :taggings, :taggable_id
        remove_index :taggings, :tag_id
      end
    end
    
    drop_table :rtag_dummy
  end
end
