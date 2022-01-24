# frozen_string_literal: true

module Extension
  module Models
    module SpecificationHandlers
      class CheckoutUiExtension < Default
        L10N_DIRECTORY = "locales"
        L10N_BASE64_MODE = "rt"
        L10N_BASE64_ENCODING = "UTF-8"
        L10N_SIZE_LIMIT = 64 * 1024 # 64kb TODO decide on size limit per file
        L10N_DEFAULT_LOCALE_REGEX = /[a-z]{2,3}(-[A-Z]{2})?\.default/
        L10N_LOCALE_REGEX = /^[a-z]{2,3}(-[A-Z]{2})?$/

        PERMITTED_CONFIG_KEYS = [:extension_points, :metafields, :name]

        def config(context)
          {
            **Features::ArgoConfig.parse_yaml(context, PERMITTED_CONFIG_KEYS),
            **argo.config(context, include_renderer_version: false),
            **localization(context)
          }
        end

        def supplies_resource_url?
          true
        end

        def build_resource_url(context:, shop:)
          product = Tasks::GetProduct.call(context, shop)
          return unless product
          format("/cart/%<variant_id>d:%<quantity>d", variant_id: product.variant_id, quantity: 1)
        end

        private

        def localization(context)
          default_locale = nil
          Dir.chdir(context.root) do
            locale_filenames = Dir["**/*"].select { |filename| File.file?(filename) && validate_l10n_file(filename) }
            # Localization is optional
            if locale_filenames.size == 0
              return {}
            end

            default_locale_matches = locale_filenames.grep(L10N_DEFAULT_LOCALE_REGEX)
            if default_locale_matches.size != 1
              raise Extension::Errors::SingleDefaultLocaleError,
                "There must be one and only one locale identified as the default locale."
            end
            default_locale = File.basename(File.basename(default_locale_matches.first, ".json"), ".default")

            locale_filenames.map do |filename|
              locale = File.basename(File.basename(filename, ".json"), ".default")
              [locale, Base64.encode64(File.read(filename, mode: L10N_BASE64_MODE, encoding: L10N_BASE64_ENCODING))]
            end
              .yield_self do |encoded_files_by_locale|
              {
                "localization" => {
                  "default_locale" => default_locale,
                  "files" => encoded_files_by_locale.to_h,
                },
              }
            end
          end
        end

        def validate_l10n_file(filename)
          dirname = File.dirname(filename)
          # Skip files in the root of the directory tree
          return false if dirname == "."

          unless dirname == "locales"
            raise Extension::Errors::InvalidFilenameError, "Invalid directory: #{dirname}"
          end

          ext = File.extname(filename)
          if ext != ".json"
            raise Extension::Errors::InvalidFilenameError,
              "Invalid filename: #{filename}; Only .json allowed in #{dirname}"
          end

          basename = File.basename(File.basename(filename, ".json"), ".default")
          unless L10N_LOCALE_REGEX.match?(basename)
            raise Extension::Errors::InvalidFilenameError,
              "Invalid filename: #{filename}; Invalid locale format: #{basename}"
          end

          if File.size(filename) > L10N_SIZE_LIMIT
            raise Extension::Errors::FileTooLargeError,
              "Single file size must be less than #{CLI::Kit::Util.to_filesize(L10N_SIZE_LIMIT)}"
          end

          true
        end
      end
    end
  end
end
