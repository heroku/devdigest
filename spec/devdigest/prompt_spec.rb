require 'helper'
require 'devdigest/prompt'
require 'stringio'

describe Devdigest::Prompt do
  describe '.ask_for_credentials' do
    let(:username) { 'arthur' }
    let(:password) { 'towel' }
    let(:stderr)   { StringIO.new }
    let(:stdin)    { StringIO.new([ username, $/, password, $/ ].join('')) }
    subject { Devdigest::Prompt.ask_for_credentials(stdin, stderr) }

    it 'returns username and password from standard input' do
      subject.should eq [ username, password ]
    end

    it 'prints prompts to standard error' do
      subject
      expected = <<EOS.chomp
Sign into your GitHub account.
Username: \
Password (typing will be hidden): 

EOS
      stderr.string.should eq expected
    end

    context 'username with surrounding whitespace' do
      let(:username) { '  authur  ' }
      it 'strips surrounding whitespace' do
        subject.first.should eq 'authur'
      end
    end

    context 'password with surrounding whitespace' do
      let(:password) { '  towel  ' }
      it 'strips surrounding whitespace' do
        subject.last.should eq 'towel'
      end
    end
  end
end
