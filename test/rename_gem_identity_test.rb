# frozen_string_literal: true

require "test_helper"

class RenameGemIdentityTest < Minitest::Test
  def test_rename_script_is_gone
    refute File.exist?(File.expand_path("../bin/rename_gem", __dir__))
  end
end
