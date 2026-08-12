import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

enum SelectionRange {
  character,
  word,
}

extension PositionExtension on Position {
  Position? moveHorizontal(
    EditorState editorState, {
    bool forward = true,
    SelectionRange selectionRange = SelectionRange.character,
  }) {
    final node = editorState.document.nodeAtPath(path);
    if (node == null) {
      return null;
    }

    if (forward && offset == 0) {
      final previousEnd = node.previous?.selectable?.end();
      if (previousEnd != null) {
        return previousEnd;
      }

      return null;
    } else if (!forward) {
      final end = node.selectable?.end();
      if (end != null && offset >= end.offset) {
        return node.next?.selectable?.start();
      }
    }

    switch (selectionRange) {
      case SelectionRange.character:
        final delta = node.delta;
        if (delta != null) {
          return Position(
            path: path,
            offset: forward
                ? delta.prevRunePosition(offset)
                : delta.nextRunePosition(offset),
          );
        }

        return Position(path: path, offset: offset);

      case SelectionRange.word:
        final delta = node.delta;
        if (delta != null) {
          final result = forward
              ? node.selectable?.getWordBoundaryInPosition(
                  Position(
                    path: path,
                    offset: delta.prevRunePosition(offset),
                  ),
                )
              : node.selectable?.getWordBoundaryInPosition(this);
          if (result != null) {
            return forward ? result.start : result.end;
          }
        }

        return Position(path: path, offset: offset);
    }
  }

  Position? moveVertical(
    EditorState editorState, {
    bool upwards = true,
  }) {
    final node = editorState.document.nodeAtPath(path);
    final nodeRenderBox = node?.renderBox;
    final nodeSelectable = node?.selectable;
    if (node == null || nodeRenderBox == null || nodeSelectable == null) {
      return this;
    }

    final editorSelection = editorState.selection;
    final rects = editorState.selectionRects();
    if (rects.isEmpty || editorSelection == null) {
      return null;
    }

    final Rect caretRect = rects.reduce((current, next) {
      if (editorSelection.isBackward) {
        return current.bottom > next.bottom ? current : next;
      }

      return current.top <= next.top ? current : next;
    });

    // The offset of outermost part of the caret.
    // Either the top if moving upwards, or the bottom if moving downwards.
    final Offset caretOffset = editorSelection.isBackward
        ? upwards
            ? caretRect.topRight
            : caretRect.bottomRight
        : upwards
            ? caretRect.topLeft
            : caretRect.bottomLeft;

    final nodeConfig = editorState.service.rendererService
        .blockComponentBuilder(node.type)
        ?.configuration;
    if (nodeConfig == null) {
      assert(nodeConfig != null, 'Block Configuration should not be null');

      return this;
    }

    final padding = nodeConfig.padding(node);
    final nodeRect = nodeSelectable.getBlockRect();
    final nodeHeight = nodeRect.height;
    final textHeight = nodeHeight - padding.vertical;
    final caretHeight = caretRect.height;

    // Minimum (acceptable) font size
    // Consider augmenting this value to increase performance.
    const double minFontSize = 1.0;

    // If the current node is not multiline, this will be ~= 0
    // so the loop will be skipped.
    final remainingMultilineHeight = textHeight - caretHeight;

    // Linearly search for a new position.
    // It's acceptable to use a linear search because the starting point is
    // the most outer part of the caret, so:
    // - If the current node is multine:
    //   - If the caret is NOT in the first/last line: at the first iteration
    //      the cycle a new position (of the previous/next multiline's line)
    //      will be found, practically ignoring the complexity of the cycle.
    //   - If the caret is in the first/last line: this is the worst case
    //      scenario, but only if the padding choosen by the user is very
    //      large. (padding >= (multiline's textHeight - caretHeight) / 3
    //      can start to be considered large. Note that in an average bad case
    //      scenario the position will be found in 10/12 ms instead of 1/2 ms)
    // - If the current node is not multiline: the cycle will be completely
    //   skipped because `remainingMultilineHeight` would be 0.
    Position adjustCrossNodePosition(Position targetPosition) {
      if (targetPosition.path.equals(path)) {
        return targetPosition;
      }
      final targetNode = editorState.document.nodeAtPath(targetPosition.path);
      final selectable = targetNode?.selectable;
      if (selectable is State) {
        final context = (selectable as State).context;
        RenderParagraph? renderParagraph;

        void findParagraph(RenderObject? renderObject) {
          if (renderObject is RenderParagraph) {
            final textLen = renderObject.text.toPlainText().length;
            if (renderParagraph == null ||
                textLen > renderParagraph!.text.toPlainText().length) {
              renderParagraph = renderObject;
            }
          }
          renderObject?.visitChildren(findParagraph);
        }

        findParagraph(context.findRenderObject());
        if (renderParagraph != null) {
          final localCaretX = renderParagraph!.globalToLocal(caretOffset).dx;
          final maxOffset = targetNode?.delta?.toPlainText().length ?? 0;

          if (!upwards) {
            // Moving DOWN into targetNode. Ensure position lands on the FIRST visual line of targetNode.
            final firstLineDy = renderParagraph!
                .getOffsetForCaret(
                  const TextPosition(offset: 0),
                  Rect.zero,
                )
                .dy;
            final checkCaretDy = renderParagraph!
                .getOffsetForCaret(
                  TextPosition(offset: targetPosition.offset),
                  Rect.zero,
                )
                .dy;
            if (checkCaretDy > firstLineDy + 4.0) {
              var adjustedOffset = targetPosition.offset;
              while (adjustedOffset > 0) {
                adjustedOffset--;
                final caretDy = renderParagraph!
                    .getOffsetForCaret(
                      TextPosition(offset: adjustedOffset),
                      Rect.zero,
                    )
                    .dy;
                if (caretDy <= firstLineDy + 4.0) {
                  return Position(
                    path: targetPosition.path,
                    offset: adjustedOffset,
                  );
                }
                int bestOffset = 0;
                double bestDiff = double.infinity;

                for (int offset = 0; offset <= maxOffset; offset++) {
                  final caret = renderParagraph!.getOffsetForCaret(
                    TextPosition(
                      offset: offset,
                      affinity: offset == 0
                          ? TextAffinity.downstream
                          : TextAffinity.upstream,
                    ),
                    Rect.zero,
                  );
                  // Only consider offsets on the first visual line
                  if (caret.dy > firstLineDy + 4.0) {
                    break;
                  }
                  final diff = (caret.dx - localCaretX).abs();
                  if (diff <= bestDiff) {
                    bestDiff = diff;
                    bestOffset = offset;
                  }
                }

                return Position(path: targetPosition.path, offset: bestOffset);
              }
            }
          } else {
            // Moving UP into targetNode. Ensure position lands on the LAST visual line of targetNode.
            final lastLineDy = renderParagraph!
                .getOffsetForCaret(
                  TextPosition(
                    offset: maxOffset,
                    affinity: TextAffinity.upstream,
                  ),
                  Rect.zero,
                )
                .dy;

            int bestOffset = maxOffset;
            double bestDiff = double.infinity;

            for (int offset = maxOffset; offset >= 0; offset--) {
              final caret = renderParagraph!.getOffsetForCaret(
                TextPosition(
                  offset: offset,
                  affinity: TextAffinity.upstream,
                ),
                Rect.zero,
              );
              // Only consider offsets on the last visual line
              if (caret.dy < lastLineDy - 4.0) {
                break;
              }
              final diff = (caret.dx - localCaretX).abs();
              if (diff <= bestDiff) {
                bestDiff = diff;
                bestOffset = offset;
              }
            }
            return Position(path: targetPosition.path, offset: bestOffset);
          }
        }
      }
      return targetPosition;
    }

    Offset newOffset = caretOffset;
    Position? newPosition;
    for (double y = minFontSize;
        y < remainingMultilineHeight + minFontSize;
        y += minFontSize) {
      newOffset = caretOffset.translate(0, upwards ? -y : y);
      newPosition =
          editorState.service.selectionService.getPositionInOffset(newOffset);
      if (newPosition != null && newPosition != this) {
        // If the position moved to a different node, accept it directly.
        if (!newPosition.path.equals(path)) {
          return adjustCrossNodePosition(newPosition);
        }

        // If in the same node, check if the offset returned really belongs to a new visual line.
        final node = editorState.document.nodeAtPath(newPosition.path);
        final selectable = node?.selectable;

        if (selectable is State) {
          final context = (selectable as State).context;
          RenderParagraph? renderParagraph;

          void findParagraph(RenderObject? renderObject) {
            if (renderObject is RenderParagraph) {
              final textLen = renderObject.text.toPlainText().length;
              if (renderParagraph == null ||
                  textLen > renderParagraph!.text.toPlainText().length) {
                renderParagraph = renderObject;
              }
            }
            renderObject?.visitChildren(findParagraph);
          }

          findParagraph(context.findRenderObject());
          if (renderParagraph != null) {
            final oldCaretDy =
                renderParagraph!.globalToLocal(caretRect.center).dy;
            final newCaretDy = renderParagraph!
                .getOffsetForCaret(
                  TextPosition(offset: newPosition.offset),
                  Rect.zero,
                )
                .dy;

            final isNewVisualLine = upwards
                ? newCaretDy < oldCaretDy - 2.0
                : newCaretDy > oldCaretDy + 2.0;

            if (isNewVisualLine) {
              // If newPosition lands on a soft-wrap line boundary where getOffsetForCaret
              // projects the caret onto the start of the next line, adjust back 1 character
              // so the caret visually stays at the end of the target line.
              if (!upwards && newPosition.offset > 0) {
                final targetLineDy = oldCaretDy + caretRect.height;
                if (newCaretDy > targetLineDy + 4.0) {
                  final prevCaret = renderParagraph!.getOffsetForCaret(
                    TextPosition(offset: newPosition.offset - 1),
                    Rect.zero,
                  );
                  if (prevCaret.dy <= targetLineDy + 4.0) {
                    newPosition = Position(
                      path: newPosition.path,
                      offset: newPosition.offset - 1,
                    );
                  }
                }
              } else if (upwards && newPosition.offset > 0) {
                final targetLineDy = oldCaretDy - caretRect.height;
                if (newCaretDy > targetLineDy + 4.0) {
                  final prevCaret = renderParagraph!.getOffsetForCaret(
                    TextPosition(offset: newPosition.offset - 1),
                    Rect.zero,
                  );
                  if (prevCaret.dy <= targetLineDy + 4.0) {
                    newPosition = Position(
                      path: newPosition.path,
                      offset: newPosition.offset - 1,
                    );
                  }
                }
              }

              return newPosition;
            }
            // Same visual line in the same node; keep searching.
            continue;
          }
        }

        return newPosition;
      }
    }

    // If a new position has not been found, it means that the current node
    // is not multiline (or the caret is in the last line of a multiline and
    // the bottom padding is very large).
    // In this case, we can manually skip to the previous/next node position
    // by translating the new offset by the padding slice to skip.
    // Note that the padding slice to skip can exceed the node's bounds.

    // The skip is calculated as the sum of:
    // - the top/bottom padding of the current node to skip to the edge of
    //    the node content rect
    // - the top/bottom editorStyle's padding to skip the current node's
    //    padding
    // - the bottom/top editorStyle's padding to skip the previous/next node's
    //    padding

    // Note that editorStyle's top and bottom padding does not change by the
    // node, so we can shorten the calculation by using the editorStyle's
    // vertical padding.
    final globalVerticalPadding = editorState.editorStyle.padding.vertical;

    final maxSkip = upwards
        ? padding.top + globalVerticalPadding
        : padding.bottom + globalVerticalPadding;

    // Translate the new offset by the padding slice to skip.
    newOffset = newOffset.translate(0, upwards ? -maxSkip : maxSkip);

    // Determine node's global position.
    final nodeHeightOffset = nodeRenderBox.localToGlobal(Offset(0, nodeHeight));

    // Clamp the new offset to the node's bounds.
    if (upwards) {
      newOffset = Offset(
        newOffset.dx,
        math.min(newOffset.dy, nodeHeightOffset.dy),
      );
    }

    newPosition =
        editorState.service.selectionService.getPositionInOffset(newOffset);

    if (newPosition != null && newPosition != this) {
      return adjustCrossNodePosition(newPosition);
    }

    // If a new position has not been found, it means that the current node
    // is not visible on the screen. It seems happens only if upwards is true (?)
    // In this case, we can manually get the previous/next node position.
    int offset = editorSelection.end.offset;
    final Path nodePath = editorSelection.end.path;
    Path neighbourPath = upwards ? nodePath.previous : nodePath.next;
    if (neighbourPath.equals(nodePath)) {
      final last = neighbourPath.removeLast();
      neighbourPath = upwards ? neighbourPath : (neighbourPath..add(last + 1));
    }
    if (neighbourPath.isNotEmpty && !neighbourPath.equals(nodePath)) {
      final neighbour = editorState.document.nodeAtPath(neighbourPath);
      final selectable = neighbour?.selectable;
      if (selectable != null) {
        offset = offset.clamp(
          selectable.start().offset,
          selectable.end().offset,
        );

        return Position(path: neighbourPath, offset: offset);
      }
    }

    final delta = node.delta;
    if (delta != null) {
      if (upwards) {
        return Position(path: path);
      } else {
        final length = delta.length;
        // move the cursor to the end of the node
        return Position(path: path, offset: length);
      }
    }

    // The cursor is already at the top or bottom of the document.
    return this;
  }
}
