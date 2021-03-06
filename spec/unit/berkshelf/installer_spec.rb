require 'spec_helper'

module Berkshelf
  describe Installer do
    let(:berksfile) { double('berksfile') }
    let(:lockfile) { double('lockfile') }
    let(:options) { double('options') }
    let(:resolver) { double('resolver') }

    let(:source_1) { double('cookbook_source@build-essential') }
    let(:source_2) { double('cookbook_source@chef-client') }
    let(:locked_1) { double('locked_cookbook_source@build-essential-1.1.0') }
    let(:locked_2) { double('locked_cookbook_source@chef-client-0.0.4') }

    let(:version_constraint) { double('version_constraint') }

    let(:sources) { [source_1, source_2] }
    let(:locked_sources) { [locked_1, locked_2] }

    subject { ::Berkshelf::Installer.new(options) }

    before do
      ::Berkshelf::Installer.any_instance.stub(:validate_options!).and_return(true)
      ::Berkshelf::Installer.any_instance.stub(:ensure_berkshelf_directory!).and_return(true)
      ::Berkshelf::Installer.any_instance.stub(:ensure_berksfile_content!).and_return(true)
      ::Berkshelf::Installer.any_instance.stub(:ensure_berksfile!).and_return(true)
      ::Berkshelf::Installer.any_instance.stub(:options).and_return(options)

      ::Berkshelf::Installer.any_instance.stub(:berksfile).and_return(berksfile)
      berksfile.stub(:sources).and_return(sources)
      berksfile.stub(:sha).and_return('abc123')

      ::Berkshelf::Installer.any_instance.stub(:lockfile).and_return(lockfile)
      lockfile.stub(:sources).and_return(locked_sources)
      lockfile.stub(:sha).and_return('abc123')

      ::Berkshelf::Installer.any_instance.stub(:filter).and_return(sources)

      ::Berkshelf::Resolver.stub(:new).with(any_args()).and_return(resolver)
      resolver.stub(:resolve).and_return(sources)
      resolver.stub(:sources).and_return(sources)

      options.stub(:[]).with(:path).and_return(nil)

      source_1.stub(:name).and_return('build-essential')
      source_1.stub(:version_constraint).and_return(version_constraint)

      source_2.stub(:name).and_return('chef-client')
      source_2.stub(:version_constraint).and_return(version_constraint)

      locked_1.stub(:name).and_return('build-essential')
      locked_1.stub(:locked_version).and_return('1.1.0')
      locked_1.stub(:version).and_return('1.1.0')

      locked_2.stub(:name).and_return('chef-client')
      locked_2.stub(:locked_version).and_return('0.0.4')
      locked_2.stub(:version).and_return('0.0.4')

      version_constraint.stub(:satisfies?).with(any_args()).and_return(true)
    end

    #
    # Class Methods
    #
    describe '.install' do
      let(:instance) { double('instance') }

      before do
        ::Berkshelf::Installer.stub(:new).and_return(instance)
      end

      it 'creates a new instance' do
        ::Berkshelf::Installer.should_receive(:new).with(options)
        instance.should_receive(:install)
        ::Berkshelf::Installer.install(options)
      end
    end

    #
    # Instance Methods
    #
    describe '#initialize' do
      context 'with an unchanged Berksfile' do
        before do
          berksfile.stub(:sha).and_return('abc123')
          lockfile.stub(:sha).and_return('abc123')

          ::Berkshelf::Installer.any_instance.stub(:resolve).with(locked_sources).and_return([sources, locked_sources])
        end

        it 'uses the lockfile sources' do
          lockfile.should_receive(:update).with(locked_sources)
          lockfile.should_receive(:sha=).with('abc123')
          lockfile.should_receive(:save)
          subject.install
        end
      end

      context 'with a changed Berskfile' do
        before do
          berksfile.stub(:sha).and_return('abc123')
          lockfile.stub(:sha).and_return('def456')

          ::Berkshelf::Installer.any_instance.stub(:resolve).with(locked_sources).and_return([sources, locked_sources])
        end

        it 'builds a sources diff' do
          lockfile.should_receive(:update).with(locked_sources)
          lockfile.should_receive(:sha=).with('abc123')
          lockfile.should_receive(:save)
          subject.install
        end

        context 'with conflicting constraints' do
          before do
            version_constraint.stub(:satisfies?).with(any_args()).and_return(false)
          end

          it 'raises a ::Bershelf::OutdatedCookbookSource' do
            expect { subject.install }.to raise_error(::Berkshelf::OutdatedCookbookSource)
          end
        end

        context 'with unlocked sources' do
          before do
            locked_sources.stub(:find).with(any_args()).and_return(nil)
            ::Berkshelf::Installer.any_instance.stub(:resolve).with(sources).and_return([sources, locked_sources])
          end

          it 'returns just the sources' do
            lockfile.should_receive(:update).with(locked_sources)
            lockfile.should_receive(:sha=).with('abc123')
            lockfile.should_receive(:save)
            subject.install
          end
        end

        context 'with the --path option' do
          before do
            options.stub(:[]).with(:path).and_return('/tmp')
            berksfile.stub(:sha).and_return('abc123')
            lockfile.stub(:sha).and_return('abc123')
            ::Berkshelf::Installer.any_instance.stub(:vendor).and_return(nil)
            ::Berkshelf::Installer.any_instance.stub(:resolve).with(locked_sources).and_return([sources, locked_sources])
          end

          it 'vendors the cookbooks' do
            lockfile.should_receive(:update).with(locked_sources)
            lockfile.should_receive(:sha=).with('abc123')
            lockfile.should_receive(:save)
            subject.install
          end
        end
      end
    end

    describe '.vendor' do
      # Make .vendor public for testing
      let(:vendor) do
        lambda { |*args| subject.send(:vendor, *args) }
      end

      before do
        require 'chef/cookbook/chefignore'

        options.stub(:[]).with(:path).and_return('/tmp')
        ::File.should_receive(:join).once.with(Dir.pwd, 'chefignore').and_return('/current_dir/chefignore')
        ::File.should_receive(:join).once.with(Dir.pwd, 'cookbooks', 'chefignore').and_return('/current_dir/cookbooks/chefignore')

        ::FileUtils.should_receive(:mkdir_p).with('/tmp').once

        ::Berkshelf.stub(:mktmpdir).and_return('/fakepath')

        source_1.should_receive(:cookbook_name).once.and_return('build-essential')
        source_2.should_receive(:cookbook_name).once.and_return('chef-client')

        ::File.should_receive(:join).once.with('/fakepath', 'build-essential', '/').once.and_return('/fakepath/build-essential/')
        ::File.should_receive(:join).once.with('/fakepath', 'chef-client', '/').once.and_return('/fakepath/chef-client/')
        ::FileUtils.should_receive(:mkdir_p).with('/fakepath/build-essential/').once
        ::FileUtils.should_receive(:mkdir_p).with('/fakepath/chef-client/').once

        source_1.should_receive(:path).once.and_return('build-essential')
        source_2.should_receive(:path).once.and_return('chef-client')

        ::File.should_receive(:join).once.with('build-essential', '*').and_return('build-essential/*')
        ::File.should_receive(:join).once.with('chef-client', '*').and_return('chef-client/*')
        ::Dir.stub(:glob).with(any_args()).and_return(['file1', 'file2', 'file3'])

        ::FileUtils.should_receive(:cp_r).once.with(['file1', 'file2', 'file3'], '/fakepath/build-essential/').and_return(nil)
        ::FileUtils.should_receive(:cp_r).once.with(['file1', 'file2', 'file3'], '/fakepath/chef-client/').and_return(nil)

        ::FileUtils.should_receive(:remove_dir).with('/tmp', force: true)

        ::FileUtils.stub(:mv).with('/fakepath', '/tmp').and_return(nil)
        ::FileUtils.should_receive(:mv).with('/fakepath', '/tmp')
      end

      context 'without a chefignore' do
        before do
          ::File.stub(:exists?).with('/current_dir/chefignore').and_return(false)
          ::File.stub(:exists?).with('/current_dir/cookbooks/chefignore').and_return(false)
          ::Chef::Cookbook::Chefignore.should_not_receive(:new).with(any_args())
        end

        it 'returns the expanded filepath of the vendor directory' do
          expect(vendor.call(sources)).to eq('/tmp')
        end
      end

      context 'with a chefignore' do
        let(:chefignore) { double('chefignore') }

        before do
          ::File.stub(:exists?).with('/current_dir/chefignore').and_return(true)
          ::File.stub(:exists?).with('/current_dir/cookbooks/chefignore').and_return(false)
          ::Chef::Cookbook::Chefignore.stub(:new).and_return(chefignore)
        end

        it 'creates a Chefignore instance' do
          ::Chef::Cookbook::Chefignore.should_receive(:new).with('/current_dir/chefignore')
          chefignore.should_receive(:remove_ignores_from).twice.with(['file1', 'file2', 'file3']).and_return(['file1', 'file2', 'file3'])
          vendor.call(sources)
        end
      end

    end
  end
end
