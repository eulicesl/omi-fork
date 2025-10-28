import ClockKit
import SwiftUI

class ComplicationController: NSObject, CLKComplicationDataSource {

    // MARK: - Complication Configuration

    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptors = [
            CLKComplicationDescriptor(
                identifier: "omi_recording",
                displayName: "Omi Recording",
                supportedFamilies: [
                    .modularSmall,
                    .modularLarge,
                    .utilitarianSmall,
                    .utilitarianLarge,
                    .circularSmall,
                    .extraLarge,
                    .graphicCorner,
                    .graphicCircular,
                    .graphicRectangular,
                    .graphicBezel,
                    .graphicExtraLarge
                ]
            )
        ]

        handler(descriptors)
    }

    // MARK: - Timeline Configuration

    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        // Complications don't expire
        handler(nil)
    }

    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.showOnLockScreen)
    }

    // MARK: - Timeline Population

    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {

        guard let template = makeTemplate(for: complication) else {
            handler(nil)
            return
        }

        let entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
        handler(entry)
    }

    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        // No future timeline entries needed
        handler(nil)
    }

    // MARK: - Placeholder Templates

    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        handler(makeTemplate(for: complication))
    }

    // MARK: - Template Creation

    private func makeTemplate(for complication: CLKComplication) -> CLKComplicationTemplate? {
        switch complication.family {
        case .modularSmall:
            return makeModularSmallTemplate()
        case .modularLarge:
            return makeModularLargeTemplate()
        case .utilitarianSmall:
            return makeUtilitarianSmallTemplate()
        case .utilitarianLarge:
            return makeUtilitarianLargeTemplate()
        case .circularSmall:
            return makeCircularSmallTemplate()
        case .extraLarge:
            return makeExtraLargeTemplate()
        case .graphicCorner:
            return makeGraphicCornerTemplate()
        case .graphicCircular:
            return makeGraphicCircularTemplate()
        case .graphicRectangular:
            return makeGraphicRectangularTemplate()
        case .graphicBezel:
            return makeGraphicBezelTemplate()
        case .graphicExtraLarge:
            return makeGraphicExtraLargeTemplate()
        @unknown default:
            return nil
        }
    }

    // MARK: - Individual Template Makers

    private func makeModularSmallTemplate() -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateModularSmallSimpleImage()
        template.imageProvider = CLKImageProvider(onePieceImage: UIImage(systemName: "mic.fill")!)
        template.imageProvider.tintColor = .white
        return template
    }

    private func makeModularLargeTemplate() -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateModularLargeStandardBody()
        template.headerTextProvider = CLKSimpleTextProvider(text: "Omi")
        template.body1TextProvider = CLKSimpleTextProvider(text: "Tap to Record")
        return template
    }

    private func makeUtilitarianSmallTemplate() -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateUtilitarianSmallSquare()
        template.imageProvider = CLKImageProvider(onePieceImage: UIImage(systemName: "mic.fill")!)
        template.imageProvider.tintColor = .white
        return template
    }

    private func makeUtilitarianLargeTemplate() -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateUtilitarianLargeFlat()
        template.textProvider = CLKSimpleTextProvider(text: "Omi Recording")
        template.imageProvider = CLKImageProvider(onePieceImage: UIImage(systemName: "mic.fill")!)
        return template
    }

    private func makeCircularSmallTemplate() -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateCircularSmallSimpleImage()
        template.imageProvider = CLKImageProvider(onePieceImage: UIImage(systemName: "mic.fill")!)
        template.imageProvider.tintColor = .white
        return template
    }

    private func makeExtraLargeTemplate() -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateExtraLargeSimpleImage()
        template.imageProvider = CLKImageProvider(onePieceImage: UIImage(systemName: "mic.fill")!)
        template.imageProvider.tintColor = .white
        return template
    }

    private func makeGraphicCornerTemplate() -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateGraphicCornerTextImage()
        template.textProvider = CLKSimpleTextProvider(text: "Omi")
        template.imageProvider = CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "mic.fill")!)
        return template
    }

    private func makeGraphicCircularTemplate() -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateGraphicCircularImage()
        template.imageProvider = CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "mic.circle.fill")!)
        return template
    }

    private func makeGraphicRectangularTemplate() -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateGraphicRectangularStandardBody()
        template.headerTextProvider = CLKSimpleTextProvider(text: "Omi")
        template.body1TextProvider = CLKSimpleTextProvider(text: "Tap to Record")

        // Optional: Add image
        let headerImageProvider = CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "mic.fill")!)
        template.headerImageProvider = headerImageProvider

        return template
    }

    private func makeGraphicBezelTemplate() -> CLKComplicationTemplate {
        let circularTemplate = CLKComplicationTemplateGraphicCircularImage()
        circularTemplate.imageProvider = CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "mic.circle.fill")!)

        let template = CLKComplicationTemplateGraphicBezelCircularText()
        template.circularTemplate = circularTemplate
        template.textProvider = CLKSimpleTextProvider(text: "Omi Recording")
        return template
    }

    private func makeGraphicExtraLargeTemplate() -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateGraphicExtraLargeCircularImage()
        template.imageProvider = CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "mic.circle.fill")!)
        return template
    }
}
