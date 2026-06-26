-- PriorityQueue.lua
-- Min/max heap used by WorkerScheduler for task ordering

PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

function PriorityQueue.new(comparator)
    local self = setmetatable({}, PriorityQueue)
    self.heap = {}
    self.comparator = comparator or function(a, b) return a.priority > b.priority end
    return self
end

function PriorityQueue:push(item)
    table.insert(self.heap, item)
    self:_bubbleUp(#self.heap)
end

function PriorityQueue:pop()
    if #self.heap == 0 then return nil end
    local top = self.heap[1]
    local last = table.remove(self.heap)
    if #self.heap > 0 then
        self.heap[1] = last
        self:_sinkDown(1)
    end
    return top
end

function PriorityQueue:peek()
    return self.heap[1]
end

function PriorityQueue:size()
    return #self.heap
end

function PriorityQueue:isEmpty()
    return #self.heap == 0
end

function PriorityQueue:_bubbleUp(i)
    while i > 1 do
        local parent = math.floor(i / 2)
        if self.comparator(self.heap[i], self.heap[parent]) then
            self.heap[i], self.heap[parent] = self.heap[parent], self.heap[i]
            i = parent
        else
            break
        end
    end
end

function PriorityQueue:_sinkDown(i)
    local n = #self.heap
    while true do
        local left = i * 2
        local right = i * 2 + 1
        local best = i
        if left <= n and self.comparator(self.heap[left], self.heap[best]) then
            best = left
        end
        if right <= n and self.comparator(self.heap[right], self.heap[best]) then
            best = right
        end
        if best == i then break end
        self.heap[i], self.heap[best] = self.heap[best], self.heap[i]
        i = best
    end
end
