import Foundation
import Postbox

/// AyuGram anti-recall: set on a stored message instead of deleting it when the
/// server reports that someone deleted it.
public final class AyuDeletedMessageAttribute: MessageAttribute {
    /// When the deletion arrived (unix time).
    public let date: Int32

    public init(date: Int32) {
        self.date = date
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
    }
}

public extension Message {
    /// When AyuGram saw this message deleted, or nil if it was not deleted.
    var ayuDeletedDate: Int32? {
        for attribute in self.attributes {
            if let attribute = attribute as? AyuDeletedMessageAttribute {
                return attribute.date
            }
        }
        return nil
    }
}

public extension EngineMessage {
    var ayuDeletedDate: Int32? {
        return self._asMessage().ayuDeletedDate
    }
}
