# frozen_string_literal: true

require 'rspec'

# The wrapper composes the HAProxy binary package from two orthogonal properties:
#   ha_proxy.ssl_variant             openssl (default) | awslc | awslc-fips
#   ha_proxy.include_haproxy_patches false (default)   | true  -> append "-patched"
# yielding /var/vcap/packages/haproxy-<ssl_variant>[-patched]. The package name is composed
# at render time, so these specs assert the rendered path + the 3-value validation.
describe 'bin/haproxy_wrapper' do
  let(:template) { haproxy_job.template('bin/haproxy_wrapper') }

  def render(props)
    template.render({ 'ha_proxy' => props })
  end

  it 'defaults to haproxy-openssl when nothing is set' do
    expect(render({})).to include('HAPROXY_PKG="/var/vcap/packages/haproxy-openssl"')
  end

  it 'selects the plain variant package' do
    expect(render({ 'ssl_variant' => 'awslc' })).to include('HAPROXY_PKG="/var/vcap/packages/haproxy-awslc"')
    expect(render({ 'ssl_variant' => 'awslc-fips' })).to include('HAPROXY_PKG="/var/vcap/packages/haproxy-awslc-fips"')
  end

  it 'appends -patched when include_haproxy_patches is true' do
    expect(render({ 'ssl_variant' => 'awslc', 'include_haproxy_patches' => true }))
      .to include('HAPROXY_PKG="/var/vcap/packages/haproxy-awslc-patched"')
  end

  it 'patches the openssl default when only include_haproxy_patches is set' do
    expect(render({ 'include_haproxy_patches' => true }))
      .to include('HAPROXY_PKG="/var/vcap/packages/haproxy-openssl-patched"')
  end

  it 'rejects an invalid ssl_variant' do
    out = render({ 'ssl_variant' => 'bogus' })
    expect(out).to include("ha_proxy.ssl_variant='bogus' is not a valid SSL variant")
    expect(out).to include('exit 1')
  end

  it 'exports the selected package onto PATH' do
    expect(render({})).to include('export PATH=$PATH:${HAPROXY_PKG}/bin')
  end
end
