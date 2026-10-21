# frozen_string_literal: true

module RecordingStudioConversions
  # Seam for a later milestone. Collection does not mint receipts, and the
  # browser cannot supply one.
  module BrowserReceipt
    module_function

    def issue(*)
      raise NotImplementedError, "server-issued browser conversion receipts are not part of collection"
    end
  end
end
