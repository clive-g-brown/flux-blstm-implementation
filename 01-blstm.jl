# 01-blstm.jl
# 
# Julia implementation Copyright (c) 2018 Matthew C. Kelley
# 
# An implementation of the bidirectional LSTM neural net for
# speech recognition defind by Graves & Schmidhuber ([Graves, A., &
# Schmidhuber, J. (2005). Framewise phoneme classification with
# bidirectional LSTM and other neural network architectures. Neural
# Networks, 18(5-6), 602-610.]). The best results the authors report
# is after training this network using a weighted error function, then
# retraining it for 17 epochs with the categorical cross entropy
# error function. The present implementation is of their network that
# does not use retraining, for which the best results were found for
# training for around 20 epochs.

using Flux
using Flux: crossentropy, softmax, flip, sigmoid, LSTM
using JLD

# Paths to the training and test data directories
traindir = "train"
testdir = "test"

# Component layers of the bidirectional LSTM layer
forward = LSTM(26, 93)
backward = LSTM(26, 93)
output = Dense(186, 61)

"""
    BLSTM(x)
    
BLSTM layer using above LSTM layers
    
# Parameters
* **x** A 2-tuple containing the forward and backward time samples;
the first is from processing the sequence forward, and the second
is from processing it backward
    
# Returns
* The concatenation of the forward and backward LSTM predictions
"""
BLSTM(x) = vcat.(forward.(x), flip(backward, x))

"""
    model(x)

The chain of functions representing the trained model.

# Parameters
* **x** The utterance that the model should process

# Returns
* The model's predictions for each time step in `x`
"""
model(x) = softmax.(output.(BLSTM(x)))

"""
   loss(x, y)

Calculates the categorical cross-entropy loss for an utterance
    
# Parameters
* **x** Iterable containing the frames to classify
* **y** Iterable containing the labels corresponding to the frames
in `x`
    
# Returns
* The calculated loss value
    
# Side-effects
* Resets the state in the BLSTM layer
"""
function loss(x, y)
    l = sum(crossentropy.(model(x), y))
    Flux.reset!((forward, backward))
    return l
end

"""
    read_data(data_dir)

Reads in the data contained in a specified directory
    
# Parameters
* **data_dir** String of the path to the directory containing the data
    
# Return
* **Xs** Vector where each element is a vector of the frames for
one utterance
* **Ys** A vector where each element is a vector of the labels for
the frames for one utterance
"""
function read_data(data_dir)
    fnames = readdir(data_dir)

    Xs = Vector()
    Ys = Vector()
    
    for (i, fname) in enumerate(fnames)
        print(string(i) * "/" * string(length(fnames)) * "\r")
        x, y = load(joinpath(data_dir, fname), "x", "y")
        x = [x[i,:] for i in 1:size(x,1)]
        y = [y[i,:] for i in 1:size(y,1)]
        push!(Xs, x)
        push!(Ys, y)
    end
    
    return (Xs, Ys)
end

"""
    predict(x)

Make predictions on the data using the model defined above

# Parameters
* **x** An iterable containing the frames for a single utterance

# Returns
* The predicted scores for each phoneme class for each frame in `x`

# Side effects
* Resets the state in the BLSTM layer after making predictions
"""
function predict(x)
    ŷ = model(x)
    Flux.reset!((forward, backward))
    return ŷ
end

"""
    evaluate_accuracy(data)

Evaluates the accuracy of the model on a set of data; can be used
either for validation or test accuracy

# Parameters
* **data** An iterable of paired values where the first element is
all the frames for a single utterance, and the second is the
associated frame labels to compare the model's predictions against

# Returns
* The predicted accuracy value as a proportion of the number of
correct predictions over the total number of predictions made
"""
function evaluate_accuracy(data)
    correct = Vector()
    for (x, y) in data
        y = indmax.(y)
        ŷ = indmax.(predict(x))
        correct = vcat(correct,
                        [ŷ_n == y_n for (ŷ_n, y_n) in zip(ŷ, y)])
    end
    sum(correct) / length(correct)
end

println("Loading files")
Xs, Ys = read_data(traindir)
data = collect(zip(Xs, Ys))

# Move 5% (184 files) of the TIMIT data into a validation set
val_data = data[1:184]
data = data[185:length(data)]

# Begin training
println("Beginning training")

opt = Momentum(params((forward, backward, output)), 10.0^-5; ρ=0.9)
epochs = 20

for i in 1:epochs
    println("Epoch " * string(i) * "/" * string(epochs))
    data = data[shuffle(1:length(data))]
    val_data = val_data[shuffle(1:length(val_data))]
    
    Flux.train!(loss, data, opt)

    print("Validating\r")
    val_acc = evaluate_accuracy(val_data)
    println("Val acc. " * string(val_acc))
    println()
end

# Clearn up some memory
val_data = 0
data = 0
Xs = 0
Ys = 0
gc()

# Test model
print("Testing\r")
Xs_test, Ys_test = read_data(testdir)
test_data = collect(zip(Xs_test, Ys_test))
test_acc = evaluate_accuracy(test_data)
println("Test acc. " * string(test_acc))
println()
