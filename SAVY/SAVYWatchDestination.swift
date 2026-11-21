import Foundation

// SAVY's side of the Watch capture kit: how one capture becomes a SAVY entry.

extension ReminderStore: WatchCaptureDestination {
    var acceptsWatchCaptures: Bool { canSync }

    func hasEntry(forWatchCapture id: UUID) -> Bool {
        reminders.contains { $0.id == id }
    }

    func saveEntry(fromWatchCapture capture: WatchCapture) -> Bool {
        save(Reminder(watchCapture: capture))
    }
}

extension Reminder {
    /// One Watch capture as a SAVY entry. The words, written out from his recording or heard by
    /// Siri, go where Adam would have typed them: “What do I want?” for Action, Reminder and
    /// Calendar, and the first Generalization question for Social. Nothing is added that he did
    /// not say. The recording stays on this device beside the entry (WatchRecordingRow).
    init(watchCapture capture: WatchCapture) {
        self.init()
        id = capture.id
        kind = ReminderKind(rawValue: capture.kind.rawValue) ?? .action
        createdAt = capture.capturedAt
        updatedAt = capture.capturedAt

        if capture.kind == .post {
            // Generalization doc: “Common scenario is that I am out for a run and have an idea
            // hit me.” He answers only the first question, “What shining example caught my
            // attention?”, and finishes the form after the run.
            let theme = PostThemeCatalog.theme(id: "generalization") ?? PostThemeCatalog.defaultTheme
            var answers = theme.prefilledAnswers
            if let first = theme.questions.first, !answers.isEmpty {
                answers[0] = first.prompt + "\n" + capture.words
            }
            postThemeID = theme.id
            postThemeName = theme.name
            postAnswers = answers
            postAnswersContainQuestions = true
            title = autoTitle() ?? "New \(kind.label)"
        } else {
            // Nothing written out (Speech Recognition off, or no words heard): SAVY's generic
            // name, which the form replaces with his words once he types them.
            title = capture.words.isEmpty ? "New \(kind.label)" : capture.words
        }

        if let window = capture.proposedWindow {
            schedule = ReminderSchedule(
                startDate: window.start,
                endDate: window.end,
                isAllDay: window.isAllDay,
                timeZoneIdentifier: capture.timeZoneIdentifier,
                alert: window.isAllDay ? .none : .atStart
            )
            scheduleSyncVersion = 1
            dueDate = window.start
            dueTime = window.isAllDay ? nil : window.start
            endTime = window.isAllDay ? nil : window.end
        }
    }
}
