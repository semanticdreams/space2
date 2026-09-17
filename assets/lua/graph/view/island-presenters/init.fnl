(local OrderedListPresenter (require :graph/view/island-presenters/ordered-list))

(local presenters {OrderedListPresenter.kind OrderedListPresenter})

(fn presenter-for-kind [kind]
    (. presenters kind))

{:presenter-for-kind presenter-for-kind}
