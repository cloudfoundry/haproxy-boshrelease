# frozen_string_literal: true

require 'rspec'

describe 'config/certs.ttar' do
  let(:template) { haproxy_job.template('config/certs.ttar') }

  describe 'ha_proxy.ssl_pem' do
    let(:ttar) do
      template.render({
        'ha_proxy' => {
          'ssl_pem' => ssl_pem
        }
      })
    end

    context 'when ssl_pem is an array of objects' do
      let(:ssl_pem) do
        [{
          'cert_chain' => 'cert_chain 0 contents',
          'private_key' => 'private_key 0 contents'
        }, {
          'cert_chain' => 'cert_chain 1 contents',
          'private_key' => 'private_key 1 contents'
        }]
      end

      it 'has the correct contents' do
        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/cert-0.pem')).to eq(<<~EXPECTED)

          cert_chain 0 contents
          private_key 0 contents

        EXPECTED

        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/cert-1.pem')).to eq(<<~EXPECTED)

          cert_chain 1 contents
          private_key 1 contents


        EXPECTED
      end
    end

    context 'when ssl_pem is provided as an array of strings' do
      let(:ssl_pem) do
        [
          'cert 0 contents',
          'cert 1 contents'
        ]
      end

      it 'has the correct contents' do
        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/cert-0.pem')).to eq(<<~EXPECTED)

          cert 0 contents

        EXPECTED

        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/cert-1.pem')).to eq(<<~EXPECTED)

          cert 1 contents


        EXPECTED
      end
    end

    context 'when ssl_pem is provided as a string' do
      let(:ssl_pem) { 'cert 0 contents' }

      it 'has the correct contents' do
        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/cert-0.pem').strip).to eq('cert 0 contents')
      end
    end
  end

  describe 'ha_proxy.crt_list' do
    describe 'ha_proxy.crt_list[].ssl_pem' do
      let(:ttar) do
        template.render({
          'ha_proxy' => {
            'crt_list' => [{
              'ssl_pem' => ssl_pem
            }]
          }
        })
      end

      context 'when ssl_pem is a string' do
        let(:ssl_pem) { 'cert 0 contents' }

        it 'has the correct contents' do
          expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/cert-0.pem')).to eq(<<~EXPECTED)

            cert 0 contents

          EXPECTED
        end

        it 'is referenced in the crt-list' do
          expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)

            /var/vcap/jobs/haproxy/config/ssl/cert-0.pem


          EXPECTED
        end
      end

      context 'when ssl_pem is an array' do
        let(:ssl_pem) do
          {
            'cert_chain' => 'cert_chain 0 contents',
            'private_key' => 'private_key 0 contents'
          }
        end

        it 'has the correct contents' do
          expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/cert-0.pem')).to eq(<<~EXPECTED)

            cert_chain 0 contents
            private_key 0 contents

          EXPECTED
        end

        it 'is referenced in the crt-list' do
          expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)

            /var/vcap/jobs/haproxy/config/ssl/cert-0.pem


          EXPECTED
        end
      end
    end

    describe 'ha_proxy.crt_list[].client_ca_file' do
      let(:ttar) do
        template.render({
          'ha_proxy' => {
            'crt_list' => [{
              'ssl_pem' => 'ssl_pem contents',
              'client_ca_file' => 'client_ca_file contents'
            }]
          }
        })
      end

      it 'references the client ca file in the crt-list' do
        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)

          /var/vcap/jobs/haproxy/config/ssl/cert-0.pem [ca-file /var/vcap/jobs/haproxy/config/ssl/ca-file-0.pem]


        EXPECTED
      end

      it 'has the correct ca file contents' do
        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/ca-file-0.pem')).to eq(<<~EXPECTED)

          client_ca_file contents

        EXPECTED
      end

      context 'when ha_proxy.client_ca_file is also configured globally' do
        let(:ttar) do
          template.render({
            'ha_proxy' => {
              'crt_list' => [{
                'client_ca_file' => 'client_ca_file contents'
              }],
              'client_ca_file' => 'client_ca_file contents'
            }
          })
        end

        it 'aborts with a meaningful error message' do
          expect do
            ttar
          end.to raise_error /Conflicting configuration. Please configure 'client_ca_file' either globally OR in 'crt_list' entries, but not both/
        end
      end
    end

    describe 'ha_proxycrt_list[].client_revocation_list' do
      let(:ttar) do
        template.render({
          'ha_proxy' => {
            'crt_list' => [{
              'ssl_pem' => 'ssl_pem contents',
              'client_revocation_list' => 'client_revocation_list contents'
            }]
          }
        })
      end

      it 'references the revocation list in the crt-list' do
        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)

          /var/vcap/jobs/haproxy/config/ssl/cert-0.pem [crl-file /var/vcap/jobs/haproxy/config/ssl/crl-file-0.pem]


        EXPECTED
      end

      it 'has the correct crl file contents' do
        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crl-file-0.pem')).to eq(<<~EXPECTED)

          client_revocation_list contents

        EXPECTED
      end

      context 'when ha_proxy.client_revocation_list is also configured globally' do
        let(:ttar) do
          template.render({
            'ha_proxy' => {
              'crt_list' => [{
                'client_revocation_list' => 'client_revocation_list contents'
              }],
              'client_revocation_list' => 'client_revocation_list contents'
            }
          })
        end

        it 'aborts with a meaningful error message' do
          expect do
            ttar
          end.to raise_error /Conflicting configuration. Please configure 'client_revocation_list' either globally OR in 'crt_list' entries, but not both/
        end
      end
    end

    describe 'ha_proxy.crt_list[].verify' do
      let(:ttar) do
        template.render({
          'ha_proxy' => {
            'crt_list' => [{
              'verify' => 'required',
              'ssl_pem' => 'ssl_pem contents'
            }]
          }
        })
      end

      it 'is included in the crt list' do
        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)

          /var/vcap/jobs/haproxy/config/ssl/cert-0.pem [verify required]


        EXPECTED
      end
    end

    describe 'ha_proxy.crt_list[].snifilter' do
      let(:ttar) do
        template.render({
          'ha_proxy' => {
            'crt_list' => [{
              'snifilter' => snifilter,
              'ssl_pem' => 'ssl_pem contents'
            }]
          }
        })
      end

      context 'when snilter is an array' do
        let(:snifilter) do
          [
            '*.domain.tld',
            '!secure.domain.tld'
          ]
        end

        it 'is included in the crt list' do
          expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)

            /var/vcap/jobs/haproxy/config/ssl/cert-0.pem *.domain.tld !secure.domain.tld


          EXPECTED
        end
      end

      context 'when snilter is a string' do
        let(:snifilter) { '*.domain.tld' }

        it 'is included in the crt list' do
          expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)

            /var/vcap/jobs/haproxy/config/ssl/cert-0.pem *.domain.tld


          EXPECTED
        end
      end
    end

    describe 'ha_proxy.crt_list[].ssl_ciphers' do
      let(:ttar) do
        template.render({
          'ha_proxy' => {
            'crt_list' => [{
              'ssl_ciphers' => 'AES:ALL:!aNULL:!eNULL:+RC4:@STRENGTH',
              'ssl_pem' => 'ssl_pem contents'
            }]
          }
        })
      end

      it 'is included in the crt list' do
        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)

          /var/vcap/jobs/haproxy/config/ssl/cert-0.pem [ciphers AES:ALL:!aNULL:!eNULL:+RC4:@STRENGTH]


        EXPECTED
      end
    end

    describe 'ha_proxy.crt_list[].ssl_ciphersuites' do
      let(:ttar) do
        template.render({
          'ha_proxy' => {
            'crt_list' => [{
              'ssl_ciphersuites' => 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384',
              'ssl_pem' => 'ssl_pem contents'
            }]
          }
        })
      end

      it 'is included in the crt list' do
        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)

          /var/vcap/jobs/haproxy/config/ssl/cert-0.pem [ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384]


        EXPECTED
      end
    end
  end

  describe 'ha_proxy.crt_list[].ssl_min_version' do
    let(:ttar) do
      template.render({
        'ha_proxy' => {
          'crt_list' => [{
            'ssl_min_version' => 'TLSv1.2',
            'ssl_pem' => 'ssl_pem contents'
          }]
        }
      })
    end

    it 'is included in the crt list' do
      expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)

        /var/vcap/jobs/haproxy/config/ssl/cert-0.pem [ssl-min-ver TLSv1.2]


      EXPECTED
    end
  end

  describe 'ha_proxy.crt_list[].ssl_max_version' do
    let(:ttar) do
      template.render({
        'ha_proxy' => {
          'crt_list' => [{
            'ssl_max_version' => 'TLSv1.2',
            'ssl_pem' => 'ssl_pem contents'
          }]
        }
      })
    end

    it 'is included in the crt list' do
      expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)

        /var/vcap/jobs/haproxy/config/ssl/cert-0.pem [ssl-max-ver TLSv1.2]


      EXPECTED
    end
  end

  describe 'ha_proxy.crt_list[].ssl_max_version and ha_proxy.crt_list[].ssl_max_version' do
    let(:ttar) do
      template.render({
        'ha_proxy' => {
          'crt_list' => [{
            'ssl_min_version' => 'TLSv1.2',
            'ssl_max_version' => 'TLSv1.2',
            'ssl_pem' => 'ssl_pem contents'
          }]
        }
      })
    end

    it 'is included in the crt list' do
      expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)

        /var/vcap/jobs/haproxy/config/ssl/cert-0.pem [ssl-min-ver TLSv1.2 ssl-max-ver TLSv1.2]


      EXPECTED
    end
  end

  describe 'ha_proxy.ext_crt_list' do
    context 'when there are no internal certificates' do
      let(:ttar) do
        template.render({
          'ha_proxy' => {
            'crt_list' => [],
            'ext_crt_list' => true
          }
        })
      end

      it 'is referenced in the crt list' do
        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)


          #OPTIONAL_EXT_CERTS

        EXPECTED
      end
    end

    context 'when there are also internal certificates' do
      let(:ttar) do
        template.render({
          'ha_proxy' => {
            'crt_list' => [{
              'ssl_pem' => 'ssl_pem 0 contents'
            }, {
              'ssl_pem' => 'ssl_pem 1 contents'
            }],
            'ext_crt_list' => true
          }
        })
      end

      it 'is referenced in the crt list' do
        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/crt-list')).to eq(<<~EXPECTED)

          /var/vcap/jobs/haproxy/config/ssl/cert-0.pem
          /var/vcap/jobs/haproxy/config/ssl/cert-1.pem

          #OPTIONAL_EXT_CERTS

        EXPECTED
      end

      it 'has the correct internal certificate contents' do
        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/cert-0.pem')).to eq(<<~EXPECTED)

          ssl_pem 0 contents

        EXPECTED

        expect(ttar_entry(ttar, '/var/vcap/jobs/haproxy/config/ssl/cert-1.pem')).to eq(<<~EXPECTED)

          ssl_pem 1 contents

        EXPECTED
      end
    end
  end

  context 'when no certificate-related properties are provided' do
    it 'is empty' do
      expect(template.render({})).to be_a_blank_string
    end
  end
end
