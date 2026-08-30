import Foundation

/// The one place the @ort handle and its link live. Three screens carry
/// the byline (splash footer, settings footer, About sheet) and they
/// must not drift apart.
enum Credits {
    static let ortURL = "https://instagram.com/ort"

    /// Turns every bare `@ort` in `raw` into a link. Pass plain text,
    /// not markdown, so there's only one spelling of the handle in the
    /// source.
    static func linkedOrt(_ raw: String) -> AttributedString {
        let markdown = raw.replacingOccurrences(of: "@ort", with: "[@ort](\(ortURL))")
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(raw)
    }
}
