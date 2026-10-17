#!/usr/bin/env ruby
# frozen_string_literal: true

# Exercise the formula's generated site-start.el in a real Emacs.
# Run with: ruby tests/test_formula_path.rb (EMACS can select the executable).

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'
require 'yaml'

# Homebrew provides these base classes; the generator itself needs no brew runtime.
class Formula; end unless defined?(Formula)
class AbstractFileDownloadStrategy; end unless defined?(AbstractFileDownloadStrategy)
HOMEBREW_PREFIX = '/opt/homebrew' unless defined?(HOMEBREW_PREFIX)

require_relative '../Library/EmacsBase'

class PathTestFormula < EmacsBase
  attr_reader :share

  def initialize(share)
    @share = share
  end

  def ohai(*); end
end

class TestBottleInjectedPath < Minitest::Test
  WORKFLOW = File.expand_path('../.github/workflows/build-bottle.yml', __dir__)

  def test_default_and_scheduled_paths_keep_home_entries_unexpanded
    workflow = YAML.load_file(WORKFLOW)
    # Psych's YAML 1.1 parser may interpret the GitHub Actions `on` key as true.
    triggers = workflow['on'] || workflow[true]
    default = triggers.fetch('workflow_dispatch').fetch('inputs').fetch('inject_path').fetch('default')

    scheduled = injected_path('')
    assert_equal default, scheduled
    assert_equal '~/.config/herd-lite/bin', scheduled.split(':').first
    assert_includes scheduled.split(':'), '~/.orbstack/bin'
    refute_includes scheduled, '/Users/'
  end

  def test_manual_override_keeps_home_entries_unexpanded
    assert_equal '~/tools:/custom/bin', injected_path('~/tools:/custom/bin')
  end

  def injected_path(input)
    step = YAML.load_file(WORKFLOW).fetch('jobs').fetch('bottle').fetch('steps').find do |entry|
      entry['name'] == 'Set PATH to inject into bottle'
    end
    interpolate = ->(value) { value.gsub('${{ inputs.inject_path }}', input) }
    Dir.mktmpdir('bottle-path') do |dir|
      output = File.join(dir, 'github-env')
      env = { 'HOME' => '/Users/runner', 'GITHUB_ENV' => output }
      step.fetch('env', {}).each { |key, value| env[key] = interpolate.call(value) }
      _, stderr, status = Open3.capture3(env, 'bash', '-eu', '-c', interpolate.call(step.fetch('run')))
      assert status.success?, stderr
      File.read(output).strip.delete_prefix('HOMEBREW_EMACS_PLUS_INJECT_PATH=')
    end
  end
end

class TestClientPath < Minitest::Test
  def test_client_shell_resolves_home_paths_without_expanding_other_shell_syntax
    path = %q{~/.local/bin:~:~/John's tools:/opt/a"b:$HOME/literal:/opt/back\slash}
    assignment = EmacsBase.applescript_path_assignment(path)
    # Parse the generated string with AppleScript, as Emacs Client.app does.
    shell_assignment, stderr, status = Open3.capture3('osascript', '-e', %(return "#{assignment}"))
    assert status.success?, stderr

    ['/Users/ryan', '/Users/ryan.k'].each do |home|
      stdout, stderr, status = Open3.capture3(
        { 'HOME' => home }, '/bin/sh', '-c', "#{shell_assignment.strip} /usr/bin/printenv PATH"
      )
      assert status.success?, stderr
      assert_equal "#{home}/.local/bin:#{home}:#{home}/John's tools:/opt/a\"b:$HOME/literal:/opt/back\\slash",
                   stdout.chomp
    end
  end
end

class TestFormulaPath < Minitest::Test
  def setup
    @emacs = ENV.fetch('EMACS', 'emacs')
    available = if @emacs.include?(File::SEPARATOR)
      File.executable?(@emacs)
    else
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
        File.executable?(File.join(dir, @emacs))
      end
    end
    skip 'Emacs is required to test generated startup code; set EMACS to its executable' unless available

    @tmpdir = Dir.mktmpdir('formula-path')
    PathTestFormula.new(@tmpdir).inject_emacs_plus_site_lisp(32)
    @site_start = File.join(@tmpdir, 'emacs/site-lisp/site-start.el')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir
  end

  def startup(home:, injected_path:)
    expression = <<~ELISP
      (progn
        (require 'json)
        (princ (json-encode
                (list :path (getenv "PATH")
                      :exec_path (vconcat exec-path)
                      :exec_directory exec-directory
                      :subprocess_path (car (process-lines "/usr/bin/printenv" "PATH"))
                      :injected (if ns-emacs-plus-injected-path t :json-false)))))
    ELISP
    stdout, stderr, status = Open3.capture3(
      { 'HOME' => home, 'EMACS_PLUS_PATH' => injected_path },
      @emacs, '-Q', '--batch', '--load', @site_start, '--eval', expression
    )
    assert status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal result.fetch('path'), result.fetch('subprocess_path')
    result
  end

  def test_absolute_and_other_relative_paths_are_preserved
    path = '/opt/homebrew/bin:/opt/custom/../bin:relative/bin:/opt/~keep/bin:~someone/bin:/usr/bin'
    result = startup(home: '/Users/ryan.k', injected_path: path)

    assert_equal path, result.fetch('path')
    assert_equal path.split(':') + [result.fetch('exec_directory')], result.fetch('exec_path')
  end

  def test_bare_tilde_resolves_to_the_current_home
    result = startup(home: '/Users/ryan.k', injected_path: '~:/usr/bin')

    assert_equal '/Users/ryan.k:/usr/bin', result.fetch('path')
  end

  def test_absent_injected_path_leaves_the_environment_alone
    result = startup(home: '/Users/ryan.k', injected_path: nil)

    assert_equal ENV.fetch('PATH'), result.fetch('path')
    assert_equal false, result.fetch('injected')
  end

  def test_same_startup_file_resolves_home_paths_for_each_user
    ['/Users/ryan', '/Users/ryan.k'].each do |home|
      result = startup(home: home, injected_path: '~/.local/bin:~/.cargo/bin:/opt/homebrew/bin:/usr/bin')
      expected = ["#{home}/.local/bin", "#{home}/.cargo/bin", '/opt/homebrew/bin', '/usr/bin']

      assert_equal expected.join(':'), result.fetch('path')
      assert_equal expected + [result.fetch('exec_directory')], result.fetch('exec_path')
      assert_equal true, result.fetch('injected')
    end
  end
end
