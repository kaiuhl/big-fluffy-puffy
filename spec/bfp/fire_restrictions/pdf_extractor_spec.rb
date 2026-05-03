require_relative "../../spec_helper"
require_relative "../../../lib/bfp/fire_restrictions/extractors/pdf_extractor"

RSpec.describe BFP::FireRestrictions::Extractors::PdfExtractor do
  it "extracts text from a normal text PDF" do
    page = instance_double("PDF::Reader::Page", text: "Stage 2 fire restrictions prohibit campfires.")
    reader = instance_double(PDF::Reader, pages: [page], page_count: 1)
    allow(PDF::Reader).to receive(:new).and_return(reader)

    result = described_class.new.extract("pdf bytes", final_url: "https://example.test/order.pdf")

    expect(result[:extraction_status]).to eq("ok")
    expect(result[:extracted_text]).to include("Stage 2 fire restrictions")
    expect(result[:metadata_json]).to eq(page_count: 1)
  end

  it "marks scanned or empty PDFs for review" do
    page = instance_double("PDF::Reader::Page", text: "")
    reader = instance_double(PDF::Reader, pages: [page], page_count: 1)
    allow(PDF::Reader).to receive(:new).and_return(reader)

    result = described_class.new.extract("pdf bytes", final_url: "https://example.test/scanned.pdf")

    expect(result[:extraction_status]).to eq("needs_review")
    expect(result[:extraction_error]).to include("no extractable text")
  end
end
