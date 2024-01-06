# frozen_string_literal: true

require 'rails_helper'
require "#{Rails.root}/lib/reference_counter_api"

describe ReferenceCounterApi do
  before { stub_wiki_validation }

  let(:en_wikipedia) { Wiki.get_or_create(language: 'en', project: 'wikipedia') }
  let(:es_wiktionary) { Wiki.get_or_create(language: 'es', project: 'wiktionary') }
  let(:wikidata) { Wiki.get_or_create(language: nil, project: 'wikidata') }
  let(:deleted_rev_id) { 708326238 }
  let(:rev_id) { 5006942 }

  it 'raises InvalidProjectError if using wikidata project' do
    expect do
      described_class.new(wikidata)
    end.to raise_error(described_class::InvalidProjectError)
  end

  it 'returns the number of references if response is 200 OK', vcr: true do
    ref_counter_api = described_class.new(es_wiktionary)
    number_of_references = ref_counter_api.get_number_of_references_from_revision_id rev_id
    expect(number_of_references).to eq(4)
  end

  it 'returns nil and logs the message if revision id is not 200 OK', vcr: true do
    ref_counter_api = described_class.new(en_wikipedia)
    expect(Sentry).to receive(:capture_message).with(
      'Non-200 response hitting references counter API',
      level: 'warning',
      extra: {
        project_code: 'wikipedia',
        language_code: 'en',
        rev_id: 708326238,
        status_code: 404,
        content: {
            'description' =>
            "You don't have permission to view deleted text or changes between deleted revisions."
        }
      }
    )
    number_of_references = ref_counter_api.get_number_of_references_from_revision_id deleted_rev_id
    expect(number_of_references).to eq(nil)
  end

  it 'returns nil and logs the error if an unexpected error raises', vcr: true do
    reference_counter_api = described_class.new(es_wiktionary)

    allow_any_instance_of(Faraday::Connection).to receive(:get)
      .and_raise(Faraday::TimeoutError)

    expect_any_instance_of(described_class).to receive(:log_error).with(
      Faraday::TimeoutError,
      update_service: nil,
      sentry_extra: {
         project_code: 'wiktionary',
         language_code: 'es',
         rev_id: 5006942
     }
    )
    number_of_references = reference_counter_api.get_number_of_references_from_revision_id rev_id
    expect(number_of_references).to eq(nil)
  end
end
