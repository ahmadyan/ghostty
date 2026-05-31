const GhosttyXCFramework = @This();

const std = @import("std");
const Config = @import("Config.zig");
const SharedDeps = @import("SharedDeps.zig");
const GhosttyLib = @import("GhosttyLib.zig");
const XCFrameworkStep = @import("XCFrameworkStep.zig");
const Target = @import("xcframework.zig").Target;

xcframework: *XCFrameworkStep,
target: Target,

pub fn init(
    b: *std.Build,
    deps: *const SharedDeps,
    target: Target,
) !GhosttyXCFramework {
    // Generate a headers directory with only ghostty.h and the module
    // map. We can't use include/ directly because it also contains the
    // libghostty-vt headers under include/ghostty/, which would trigger
    // "umbrella header does not include header" warnings from Clang's
    // module system.
    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(b.path("include/ghostty.h"), "ghostty.h");
    _ = wf.addCopyFile(b.path("include/module.modulemap"), "module.modulemap");
    const headers = wf.getDirectory();

    // The xcframework wraps our ghostty library so that we can link
    // it to the final app built with Swift.
    const xcframework = XCFrameworkStep.create(b, .{
        .name = "GhosttyKit",
        .out_path = "macos/GhosttyKit.xcframework",
        .libraries = switch (target) {
            // macOS-only: we intentionally drop the iOS/iOS-sim slices the
            // upstream build emits. The Agentastic app links only the macOS
            // library, and building the iOS slices fails under our toolchain.
            .universal => blk: {
                // Universal macOS build (arm64 + x86_64)
                const macos_universal = try GhosttyLib.initMacOSUniversal(b, deps);

                break :blk &.{
                    .{
                        .library = macos_universal.output,
                        .headers = headers,
                        .dsym = macos_universal.dsym,
                    },
                };
            },

            .native => blk: {
                // Native macOS build
                const macos_native = try GhosttyLib.initStatic(b, &try deps.retarget(
                    b,
                    Config.genericMacOSTarget(b, null),
                ));

                break :blk &.{.{
                    .library = macos_native.output,
                    .headers = headers,
                    .dsym = macos_native.dsym,
                }};
            },
        },
    });

    return .{
        .xcframework = xcframework,
        .target = target,
    };
}

pub fn install(self: *const GhosttyXCFramework) void {
    const b = self.xcframework.step.owner;
    self.addStepDependencies(b.getInstallStep());
}

pub fn addStepDependencies(
    self: *const GhosttyXCFramework,
    other_step: *std.Build.Step,
) void {
    other_step.dependOn(self.xcframework.step);
}
