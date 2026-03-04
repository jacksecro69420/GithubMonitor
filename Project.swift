import ProjectDescription

let project = Project(
    name: "GithubMonitor",
    organizationName: "Dimillian",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.10",
            "MACOSX_DEPLOYMENT_TARGET": "14.0"
        ]
    ),
    targets: [
        .target(
            name: "GithubMonitor",
            destinations: .macOS,
            product: .app,
            bundleId: "com.dimillian.GithubMonitor",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": true,
                "GitHubOAuthClientID": "Ov23liFsaI8OBg0R8qH8"
            ]),
            sources: ["Sources/**"]
        )
    ]
)
