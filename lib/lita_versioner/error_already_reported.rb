module LitaVersioner
  class ErrorAlreadyReported < StandardError
    attr_accessor :cause

    def initialize(message = nil, cause = nil)
      super(message)
      self.cause = cause
    end
  end
end
