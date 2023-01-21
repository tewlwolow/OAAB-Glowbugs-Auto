local util = {}

function util.nonRepeatNumberRNG(min, max)
    local n = 0
    return function()
        n = (n + math.random(min, max - 1) - 1) % max + 1
        return n
    end
end

function util.nonRepeatTableRNG(t)
    local randomIndex = util.nonRepeatNumberRNG(1, #t)

    return function()
        return t[randomIndex()]
    end
end

return util