-- Georgia Institute of Technology 
-- CS8803DL Spring 2016 (Instructor: Zsolt Kira)
-- Final Project: Video Classification

-- This script implements a test procedure, to report accuracy on the test data

-- TODO:
-- 1. 
-- 2. 

-- modified by Min-Hung Chen
-- contact: cmhungsteve@gatech.edu
-- Last updated: 10/11/2016


require 'torch'   -- torch
require 'xlua'    -- xlua provides useful tools, like progress bars
require 'optim'   -- an optimization package, for online and batch methods
require 'image'


----------------------------------------------------------------------
-- Save light network tools:
function nilling(module)
   module.gradBias   = nil
   if module.finput then module.finput = torch.Tensor() end
   module.gradWeight = nil
   module.output     = torch.Tensor()
   if module.fgradInput then module.fgradInput = torch.Tensor() end
   module.gradInput  = nil
end

function netLighter(network)
   nilling(network)
   if network.modules then
      for _,a in ipairs(network.modules) do
         netLighter(a)
      end
   end
end

----------------------------------------------------------------------
print(sys.COLORS.red .. '==> defining some tools')

-- model:
if opt.model == 'TCNN-1' then
  t = require 'model-1L'
elseif opt.model == 'TCNN-2' then
  t = require 'model-2L'
end  

local model = t.model
-- local loss = t.loss
local model_name = t.model_name
local nframeAll = t.nframeAll
local nframeUse = t.nframeUse
local nfeature = t.nfeature

-- This matrix records the current confusion across classes
local confusion = optim.ConfusionMatrix(classes) 

-- Logger:
local testLogger = optim.Logger(paths.concat(opt.save,'test.log'))

-- Batch test:
local inputs = torch.Tensor(opt.batchSize,1, nfeature, nframeUse) -- get size from data
local targets = torch.Tensor(opt.batchSize)
if opt.type == 'cuda' then 
   inputs = inputs:cuda()
   targets = targets:cuda()
end

----------------------------------------------------------------------
print(sys.COLORS.red .. '==> defining test procedure')

accMax = 0 -- record the highest testing accuracy
epoBest = 0 -- record the epoch # of the best testing accuracy

-- test function
function test(testData, classes, epo)
   model:evaluate()

   local bSize = opt.batchSize
   
   -- local vars
   local time = sys.clock()
   
   -- test over test data
   print(sys.COLORS.red .. '==> testing on test set:')
   local predlabeltxt = {}
   local prob = {}
   for t = 1,testData:size(),opt.batchSize do
      -- disp progress
	  collectgarbage()
      xlua.progress(t, testData:size())

      -- batch fits?
      if (t + bSize - 1) > testData:size() then
         bSize = testData:size() - (t-1)
         -- break
      end

      -- create mini batch
      local frameSkip = nframeAll-nframeUse
      local idx = 1
      for i = t,t+bSize-1 do
         --inputs[{idx,1}] = testData.data[{i,{},{1,nframeUse}}]
         inputs[{idx,1}] = testData.data[{i,{},{1+frameSkip/2,nframeAll-frameSkip/2}}] -- take the middle part
	      targets[idx] = testData.labels[i]
         idx = idx + 1
      end

      -- test sample
      local preds = model:forward(inputs)
      preds = preds[{{1,bSize}}] -- for the last few test data

      -- Get the top N class indexes and probabilities
      local N = 3
      local probLog, predLabels = preds:topk(N, true, true)

      -- Convert log probabilities back to [0, 1]
      probLog:exp()

      -- --print(preds:size())
      -- _,indices = torch.sort(preds,2,true)
      -- predlabels = indices[{{},1}]
      -- --print(predlabels:size())

      
      for i = 1,bSize do
         --predlabeltxt[i-1+t] = classes[predlabels[i]]
         predlabeltxt[i-1+t] = {}
         prob[i-1+t] = {}
         for j = 1, N do
            predlabeltxt[i-1+t][j] = classes[predLabels[i][j]]
            prob[i-1+t][j] = probLog[i][j]
         end

      end

      -- idx = 1
      -- for i = t,t+bSize-1 do
      --    -- inputs[{idx,1}] = testData.data[{i,{},{1,nframeUse}}]
      --    -- targets[idx] = testData.labels[i]
      --    predlabeltxt[i] = classes[predlabels[idx]]
      --    idx = idx + 1
      -- end


      -- confusion
      for i = 1,bSize do
         confusion:add(preds[i], targets[i])
      end
   end

   -- timing
   time = sys.clock() - time
   time = time / testData:size()
   print("\n==> time to test 1 sample = " .. (time*1000) .. 'ms')

   -- print confusion matrix
   print(confusion)

   -- update log/plot
   testLogger:add{['% mean class accuracy (test set)'] = confusion.totalValid * 100}
   if confusion.totalValid > accMax then
      print(sys.COLORS.yellow ..  'Updating the predicted labels!!!')
      accMax = confusion.totalValid
      epoBest = epo
      torch.save('labels.txt',predlabeltxt,'ascii')
      torch.save('prob.txt',prob,'ascii')

      -- save/log current net
      local filename = paths.concat(opt.save, model_name..'.t7')
      -- os.execute('mkdir -p ' .. sys.dirname(filename))
      print('==> saving model to '..filename)
      --model1 = model:clone()
      --netLighter(model1)
      torch.save(filename, model)
   end
   print("\n the max accuracy is " .. accMax ..' in the epoch '.. epoBest)

   if opt.plot == 'yes' then
      testLogger:style{['% mean class accuracy (test set)'] = '-'}
      testLogger:plot()
   end
   confusion:zero()
end

-- Export:
return test

