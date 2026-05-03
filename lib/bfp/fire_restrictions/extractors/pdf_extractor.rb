require "pdf-reader"
require "stringio"

module BFP
  module FireRestrictions
    module Extractors
      class PdfExtractor
        def extract(body, final_url: nil)
          reader = PDF::Reader.new(StringIO.new(body.to_s))
          pages = reader.pages.map { |page| page.text.to_s }
          text = pages.join("\n\n").gsub(/[ \t]+/, " ").strip

          if text.empty?
            return {
              canonical_url: final_url,
              extracted_text: "",
              extraction_status: "needs_review",
              extraction_error: "PDF had no extractable text; it may be scanned.",
              metadata_json: {page_count: reader.page_count}
            }
          end

          {
            title: nil,
            canonical_url: final_url,
            extracted_text: text,
            extraction_status: "ok",
            metadata_json: {page_count: reader.page_count}
          }
        rescue PDF::Reader::MalformedPDFError, ArgumentError => error
          {
            canonical_url: final_url,
            extracted_text: "",
            extraction_status: "needs_review",
            extraction_error: "#{error.class}: #{error.message}",
            metadata_json: {}
          }
        end
      end
    end
  end
end
