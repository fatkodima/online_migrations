# frozen_string_literal: true

require "zlib"

module OnlineMigrations
  # @private
  class AdvisoryLock
    attr_reader :name, :connection

    def initialize(name:, connection: ApplicationRecord.connection)
      @name = name
      @connection = connection
    end

    def try_lock
      locked = connection.select_value("SELECT pg_try_advisory_lock(#{lock_key})")
      Utils.to_bool(locked)
    end

    def unlock
      connection.select_value("SELECT pg_advisory_unlock(#{lock_key})")
    end

    # Runs the given block if an advisory lock is able to be acquired.
    def try_with_lock
      locked = try_lock
      yield if locked
    ensure
      unlock if locked
    end

    def active?
      objid = lock_key & 0xffffffff
      classid = lock_key >> 32

      active = connection.select_value(<<~SQL)
        SELECT granted
        FROM pg_locks
        WHERE locktype = 'advisory'
          AND pid = pg_backend_pid()
          AND mode = 'ExclusiveLock'
          AND classid = #{classid}
          AND objid = #{objid}
      SQL

      Utils.to_bool(active)
    end

    private
      SALT = 936723412

      def lock_key
        name_hash = Zlib.crc32(name)
        SALT * name_hash
      end
  end
end
