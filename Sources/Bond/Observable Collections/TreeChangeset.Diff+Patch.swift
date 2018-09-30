//
//  TreeChangeset.Diff+Tree+Patch.swift
//  Bond-iOS
//
//  Created by Srdan Rasic on 28/09/2018.
//  Copyright © 2018 Swift Bond. All rights reserved.
//

import Foundation

extension TreeChangeset.Diff {

    private struct Edit {

        var deletionIndex: IndexPath?
        var insertionIndex: IndexPath?
        var element: Collection.ChildNode?

        var asOperation: TreeChangeset.Operation {
            if let from = deletionIndex, let to = insertionIndex {
                return .move(from: from, to: to)
            } else if let deletionIndex = deletionIndex {
                return .delete(at: deletionIndex)
            } else if let insertionIndex = insertionIndex, let element = element {
                return .insert(element, at: insertionIndex)
            } else {
                fatalError()
            }
        }
    }

    func generatePatch(to collection: Collection) -> [TreeChangeset.Operation] {

        let inserts = self.inserts.map { Edit(deletionIndex: nil, insertionIndex: $0, element: collection[$0]) }
        let deletes = self.deletes.map { Edit(deletionIndex: $0, insertionIndex: nil, element: nil) }
        let moves = self.moves.map { Edit(deletionIndex: $0.from, insertionIndex: $0.to, element: nil) }

        func makeInsertionTree(_ script: [Edit]) -> TreeNode<Int> {
            func insert(_ edit: Edit, value: Int, into tree: TreeNode<Int>) -> TreeNode<Int> {
                var tree = tree
                if let insertionIndex = edit.insertionIndex, let index = tree.children.firstIndex(where: { script[$0.value].insertionIndex?.isAncestor(of: insertionIndex) ?? false }) {
                    tree.children[index] = insert(edit, value: value, into: tree.children[index])
                } else {
                    var newNode = TreeNode(value)
                    for (index, node) in tree.children.enumerated().reversed() {
                        if let insertionIndex = script[node.value].insertionIndex, edit.insertionIndex?.isAncestor(of: insertionIndex) ?? false {
                            tree.children.remove(at: index)
                            newNode.children.append(node)
                        }
                    }
                    newNode.children = newNode.children.reversed()
                    tree.children.insert(newNode, isOrderedBefore: { script[$0.value].insertionIndex ?? [] < script[$1.value].insertionIndex ?? [] })
                }
                return tree
            }
            var tree = TreeNode(-1)
            for (index, edit) in script.enumerated() {
                tree = insert(edit, value: index, into: tree)
            }
            return tree
        }

        func makeDeletionTree(_ script: [Edit]) -> TreeNode<Int> {
            func insert(_ edit: Edit, value: Int, into tree: TreeNode<Int>) -> TreeNode<Int> {
                var tree = tree
                if let deletionIndex = edit.deletionIndex, let index = tree.children.firstIndex(where: { script[$0.value].deletionIndex?.isAncestor(of: deletionIndex) ?? false }) {
                    tree.children[index] = insert(edit, value: value, into: tree.children[index])
                } else {
                    var newNode = TreeNode(value)
                    for (index, node) in tree.children.enumerated().reversed() {
                        if let deletionIndex = script[node.value].deletionIndex, edit.deletionIndex?.isAncestor(of: deletionIndex) ?? false {
                            tree.children.remove(at: index)
                            newNode.children.append(node)
                        }
                    }
                    newNode.children = newNode.children.reversed()
                    tree.children.insert(newNode, isOrderedBefore: { script[$0.value].deletionIndex ?? [Int.max] < script[$1.value].deletionIndex ?? [Int.max] })
                }
                return tree
            }
            var tree = TreeNode(-1)
            for (index, edit) in script.enumerated() {
                tree = insert(edit, value: index, into: tree)
            }
            return tree
        }

        let deletesAndMoves = deletes + moves
        let deletionTree = makeDeletionTree(deletesAndMoves)
        var deletionScript = Array(deletionTree.indices.map { deletesAndMoves[deletionTree[$0].value] }.reversed())
        var insertionSeedScript = deletionScript
        var moveCounter = 0
        for index in 0..<deletionScript.count {
            if deletionScript[index].deletionIndex != nil {
                deletionScript[index].deletionIndex![0] += moveCounter
                insertionSeedScript[index].deletionIndex = [moveCounter]
            }
            if deletionScript[index].insertionIndex != nil {
                deletionScript[index].insertionIndex = [moveCounter]
                moveCounter += 1
            }
        }

        let movesAndInserts = insertionSeedScript.filter { $0.insertionIndex != nil } + inserts
        let insertionTree = makeInsertionTree(movesAndInserts)
        var insertionScript = insertionTree.indices.map { movesAndInserts[insertionTree[$0].value] }

        for index in 0..<insertionScript.count {

            for j in index+1..<insertionScript.count {
                if let deletionIndex = insertionScript[j].deletionIndex, let priorDeletionIndex = insertionScript[index].deletionIndex {
                    if deletionIndex.isAffectedByDeletionOrInsertion(at: priorDeletionIndex) {
                        insertionScript[j].deletionIndex = deletionIndex.shifted(by: -1, atLevelOf: priorDeletionIndex)
                    }
                }
            }

            if insertionScript[index].insertionIndex != nil {
                if insertionScript[index].deletionIndex != nil {
                    moveCounter -= 1
                }
                insertionScript[index].insertionIndex![0] += moveCounter
            }
        }

        return (deletionScript + insertionScript).map { $0.asOperation }
    }
}