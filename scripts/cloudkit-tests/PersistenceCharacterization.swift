import Foundation

@main
struct PersistenceCharacterization {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-store-write-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let postFile = directory.appendingPathComponent("posts.json")
        let storyFile = directory.appendingPathComponent("stories.json")
        var post = SocialPost()
        post.text = "The confirmed original post."
        var story = Story()
        story.body = "The confirmed original story."
        try JSONEncoder.recall.encode([post]).write(to: postFile)
        try JSONEncoder.recall.encode([story]).write(to: storyFile)
        let posts = try SocialPostStore(fileURL: postFile)
        let stories = try StoryStore(fileURL: storyFile)
        let oldPosts = posts.posts
        let oldStories = stories.stories
        try FileManager.default.removeItem(at: postFile)
        try FileManager.default.removeItem(at: storyFile)
        try FileManager.default.createDirectory(at: postFile, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: storyFile, withIntermediateDirectories: false)
        post.text = "Fetched replacement that cannot be written."
        story.body = "Fetched replacement that cannot be written."
        posts.applySynced([post])
        stories.applySynced([story])
        let postPassed = posts.posts == oldPosts
        let storyPassed = stories.stories == oldStories
        print("\(postPassed ? "PASS" : "FAIL") failed Post write retains confirmed published content")
        print("\(storyPassed ? "PASS" : "FAIL") failed Story write retains confirmed published content")
        fflush(nil)
        guard postPassed && storyPassed else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
