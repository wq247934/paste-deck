//
//  ToolRegistry.swift
//  PasteDeck
//
//  内置工具的集中注册与查询。工具来源只有 BuiltinTool 枚举，
//  注册表负责稳定排序与按 ID 查找，保证工具 ID 唯一。
//

import Foundation

enum ToolRegistry {

    /// 全部已注册工具，按 BuiltinTool 声明顺序排列。
    static let allTools: [ToolDescriptor] = BuiltinTool.allCases.map(\.descriptor)

    static func descriptor(withID id: String) -> ToolDescriptor? {
        BuiltinTool(rawValue: id)?.descriptor
    }

    static func tool(withID id: String) -> BuiltinTool? {
        BuiltinTool(rawValue: id)
    }
}
