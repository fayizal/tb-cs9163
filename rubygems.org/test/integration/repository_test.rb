require 'minitest/unit'
require 'minitest/autorun'

require 'json'

require 'rubygems/tuf'

class TufRepositoryTest < MiniTest::Unit::TestCase
  T = Gem::TUF

  class InMemoryBucket
    def initialize
      @paths = {}
    end

    def get(path, _ = {})
      @paths[path]
    end

    def create(path, content)
      @paths[path] = content
    end

    attr_reader :paths
  end

  def test_bootstrapping_a_new_system
    offline_key = T::Key.build('insecure', '', 'offline')
    online_key  = T::Key.build('insecure', '', 'insecure')

    root = T::Role::Root.empty
    root.add_roles(
      'root'      => [offline_key],
      'targets'   => [offline_key],
      'release'   => [online_key],
      'timestamp' => [online_key],
    )

    signed_root = T::Signer.sign_unwrapped(root.to_hash, offline_key)

    repo = Tuf::OnlineRepository.new(
      bucket:     bucket = InMemoryBucket.new,
      online_key: online_key,
      root:       signed_root
    )
    repo.bootstrap!

    claimed   = T::Role::Targets.empty
    unclaimed = T::Role::Targets.empty
    recent    = T::Role::Targets.empty

    targets = T::Role::Targets.empty
    targets.delegate_to('targets/claimed', [offline_key])
    targets.delegate_to('targets/recently-claimed', [online_key])
    targets.delegate_to('targets/unclaimed', [online_key])

    signed_claimed   = T::Signer.sign_unwrapped(claimed.to_hash, offline_key)
    signed_unclaimed = T::Signer.sign_unwrapped(unclaimed.to_hash, online_key)
    signed_recent    = T::Signer.sign_unwrapped(recent.to_hash, online_key)
    signed_targets   = T::Signer.sign_unwrapped(targets.to_hash, offline_key)

    repo.add_signed_delegated_role('targets', 'root', signed_targets)
    repo.add_signed_delegated_role('targets/claimed', 'targets', signed_claimed)
    repo.add_signed_delegated_role('targets/recently-claimed', 'targets', signed_recent)
    repo.add_signed_delegated_role('targets/unclaimed', 'targets', signed_unclaimed)

    repo.publish!

    file = T::File.from_body('gems/mygem-0.0.1.gem', 'gemgemgemgemgem')

    repo.add_file(file, 'targets/unclaimed', 'targets')


    assert bucket.paths['metadata/timestamp.txt'], "timestamp is not available"

    assert_equal 'gemgemgemgemgem', bucket.paths['gems/mygem-0.0.1.gem'],     "cannot fetch file without TUF"
    assert_equal 'gemgemgemgemgem', repo.target('gems/mygem-0.0.1.gem').body, "cannot fetch file with TUF"

#     bucket.paths.each do |path, content|
#       puts
#       puts "===== #{path}"
#       puts content
#     end
  end
end
