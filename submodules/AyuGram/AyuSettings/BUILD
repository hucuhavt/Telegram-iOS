load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# AyuGram settings: plain Foundation, so that TelegramCore can read them
# on its network queues and the UI can edit them.
swift_library(
    name = "AyuSettings",
    module_name = "AyuSettings",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    visibility = [
        "//visibility:public",
    ],
)
