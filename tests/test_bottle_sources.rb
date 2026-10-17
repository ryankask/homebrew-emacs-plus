#!/usr/bin/env ruby
# frozen_string_literal: true

# Run the workflow's source-preparation steps against real temporary Git repos.
# Homebrew is replaced only at the --repository boundary; no builds or pushes.
# Run with: ruby tests/test_bottle_sources.rb

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'yaml'

class TestBottleSources < Minitest::Test
  WORKFLOW = File.expand_path('../.github/workflows/build-bottle.yml', __dir__)

  def command(*args, chdir: @workspace)
    stdout, stderr, status = Open3.capture3(@env, *args, chdir: chdir)
    assert status.success?, "#{args.inspect}: #{stderr}"
    stdout.strip
  end

  def run_step(name)
    step = YAML.load_file(WORKFLOW).fetch('jobs').fetch('bottle').fetch('steps').find do |entry|
      entry['name'] == name
    end
    refute_nil step, "Missing workflow step: #{name}"
    command('bash', '-euo', 'pipefail', '-c', step.fetch('run'))
  end

  def test_build_tap_uses_the_same_merged_sources_as_the_release_checkout
    Dir.mktmpdir('bottle-sources') do |dir|
      origin = File.join(dir, 'origin.git')
      @workspace = File.join(dir, 'workspace')
      tap = File.join(dir, 'tap')
      bin = File.join(dir, 'bin')
      FileUtils.mkdir_p([@workspace, bin])
      @env = {
        'HOME' => dir,
        'GIT_CONFIG_GLOBAL' => File::NULL,
        'GIT_CONFIG_NOSYSTEM' => '1',
        'GIT_AUTHOR_NAME' => 'Test', 'GIT_AUTHOR_EMAIL' => 'test@example.com',
        'GIT_COMMITTER_NAME' => 'Test', 'GIT_COMMITTER_EMAIL' => 'test@example.com',
        'GITHUB_WORKSPACE' => @workspace,
        'GITHUB_ENV' => File.join(dir, 'github-env'),
        'TEST_TAP' => tap,
        'PATH' => "#{bin}:#{ENV.fetch('PATH')}",
      }
      command('git', 'init', '--bare', origin)
      command('git', 'init')
      command('git', 'checkout', '-b', 'main')
      command('git', 'remote', 'add', 'origin', origin)
      File.write(File.join(@workspace, 'startup'), 'old startup')
      command('git', 'add', '.')
      command('git', 'commit', '-m', 'base')
      command('git', 'checkout', '-b', 'nightly')
      File.write(File.join(@workspace, 'bottle'), 'fork bottle block')
      command('git', 'add', '.')
      command('git', 'commit', '-m', 'nightly bottle')
      command('git', 'push', 'origin', 'nightly')
      command('git', 'checkout', 'main')
      File.write(File.join(@workspace, 'startup'), 'home-relative startup')
      command('git', 'commit', '-am', 'runtime home expansion')
      command('git', 'push', 'origin', 'main')
      command('git', '--git-dir', origin, 'symbolic-ref', 'HEAD', 'refs/heads/nightly')
      command('git', 'clone', origin, tap)
      File.write(File.join(bin, 'brew'), <<~SH)
        #!/bin/sh
        [ "$1" = --repository ] && [ "$2" = ryankask/emacs-plus ] || exit 1
        printf '%s\\n' "$TEST_TAP"
      SH
      FileUtils.chmod(0755, File.join(bin, 'brew'))

      run_step('Prepare nightly sources')
      run_step('Use prepared sources in the build tap')

      assert_equal 'home-relative startup', File.read(File.join(tap, 'startup'))
      assert_equal 'fork bottle block', File.read(File.join(tap, 'bottle'))
      assert_equal command('git', 'rev-parse', 'HEAD'), command('git', '-C', tap, 'rev-parse', 'HEAD')
      assert_equal "HOMEBREW_NO_AUTO_UPDATE=1\n", File.read(@env.fetch('GITHUB_ENV'))
      # Preparing a build must not advertise an unbuilt package to clients.
      assert_equal 'old startup', command('git', '--git-dir', origin, 'show', 'nightly:startup')
    end
  end
end
