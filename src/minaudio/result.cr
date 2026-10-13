# ma_result codes (vendor/miniaudio.h, ma_result enum) mapped to a Crystal
# enum; errors raise MinAudio::Error carrying the code.

module MinAudio
  enum Result
    SUCCESS             =   0
    ERROR               =  -1 # generic
    INVALID_ARGS        =  -2
    INVALID_OPERATION   =  -3
    OUT_OF_MEMORY       =  -4
    OUT_OF_RANGE        =  -5
    ACCESS_DENIED       =  -6
    DOES_NOT_EXIST      =  -7
    ALREADY_EXISTS      =  -8
    TOO_MANY_OPEN_FILES =  -9
    INVALID_FILE        = -10
    TOO_BIG             = -11
    PATH_TOO_LONG       = -12
    NAME_TOO_LONG       = -13
    NOT_DIRECTORY       = -14
    IS_DIRECTORY        = -15
    DIRECTORY_NOT_EMPTY = -16
    AT_END              = -17
    NO_SPACE            = -18
    BUSY                = -19
    IO_ERROR            = -20
    INTERRUPT           = -21
    UNAVAILABLE         = -22
    ALREADY_IN_USE      = -23
    BAD_ADDRESS         = -24
    BAD_SEEK            = -25
    BAD_PIPE            = -26
    DEADLOCK            = -27
    TOO_MANY_LINKS      = -28
    NOT_IMPLEMENTED     = -29
    NO_MESSAGE          = -30
    BAD_MESSAGE         = -31
    NO_DATA_AVAILABLE   = -32
    INVALID_DATA        = -33
    TIMEOUT             = -34

    def success? : Bool
      self == Result::SUCCESS
    end

    def description : String
      success? ? "success" : "#{to_s.underscore.gsub('_', ' ')} (#{value})"
    end
  end

  class Error < Exception
    getter code : Result

    def initialize(@code : Result, what : String)
      super("#{what}: #{code.description}")
    end
  end

  # Raises on a negative ma_result, returns the value otherwise.
  def self.check(code : Int32, what : String) : Int32
    if code != Result::SUCCESS.value
      raise Error.new(Result.from_value?(code) || Result::ERROR, what)
    end
    code
  end

  # Raises unless `cond` — small guard for argument checks.
  def self.assert(cond : Bool, what : String) : Nil
    raise Error.new(Result::INVALID_ARGS, what) unless cond
  end
end
