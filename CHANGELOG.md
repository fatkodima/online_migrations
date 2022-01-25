## master (unreleased)

- Add support for multiple databases to `start_after` and `target_version` configuration options

    ```ruby
    OnlineMigrations.configure do |config|
      config.start_after = { primary: 20211112000000, animals: 20220101000000 }
      config.target_version = { primary: 10, animals: 14.1 }
    end
    ```

- Do not suggest `ignored_columns` when removing columns for Active Record 4.2 (`ignored_columns` was introduced in 5.0)
- Check replacing indexes

## 0.1.0 (2022-01-17)

- First release
